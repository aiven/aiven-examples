// Command live-orders is a long-running Kafka producer that continuously streams
// mock ecommerce orders into a Kafka topic at a configurable rate, until it is
// shut down. It is the "live" data source for the aiven-trino-iceberg-agent
// demo: orders land in Kafka, flow through the Kafka Connect Iceberg sink into
// Iceberg-on-S3, and are then queryable through Trino.
//
// Unlike the one-shot producer in aiven-iceberg-tutorial, this runs forever and
// stamps each order with the current time, so the data is genuinely live.
//
// Configuration (environment variables):
//
//	KAFKA_SERVICE_URI  - SASL_SSL broker address from the Aiven Console
//	                     (Service > Connection information, authentication "SASL").
//	                     Note: a different port than the certificate/mTLS endpoint.
//	KAFKA_USERNAME     - Kafka SASL username (e.g. avnadmin)
//	KAFKA_PASSWORD     - Kafka SASL password
//	KAFKA_TOPIC        - target topic (optional, default "order")
//	ORDERS_PER_MINUTE  - target emission rate (optional, default 100)
package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/IBM/sarama"
)

func mustGetenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return v
}

// getenvDefault returns the value of key, or def if unset/empty.
func getenvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

type OrderKey struct {
	KeyId   int    `json:"keyId"`
	KeyCode string `json:"keyCode"`
}

// Order represents an ecommerce order placed by a customer. The shape matches
// the aiven-iceberg-tutorial producer so the existing Iceberg sink schema works
// unchanged.
type Order struct {
	OrderID    int     `json:"orderId"`
	CustomerID int     `json:"customerId"`
	Product    string  `json:"product"`
	Quantity   int     `json:"quantity"`
	Amount     float64 `json:"amount"`
	Status     string  `json:"status"`    // PENDING, PAID, SHIPPED, DELIVERED, CANCELLED
	OrderDate  string  `json:"orderDate"` // RFC3339 timestamp (always "now" — live data)
}

var (
	products = []string{"Laptop", "Headphones", "Keyboard", "Monitor", "Webcam", "Mouse", "Desk Chair", "USB-C Cable"}
	statuses = []string{"PENDING", "PAID", "SHIPPED", "DELIVERED", "CANCELLED"}
)

// intervalFor returns the delay between sends needed to hit a target rate.
func intervalFor(ordersPerMinute int) time.Duration {
	return time.Minute / time.Duration(ordersPerMinute)
}

// newOrderMessage builds the Kafka message (JSON key + value) for an order.
func newOrderMessage(topic string, order Order) (*sarama.ProducerMessage, error) {
	key := OrderKey{KeyId: order.OrderID * 10, KeyCode: fmt.Sprintf("O%d", order.OrderID)}
	keyBytes, err := json.Marshal(key)
	if err != nil {
		return nil, fmt.Errorf("marshal key: %w", err)
	}
	valueBytes, err := json.Marshal(order)
	if err != nil {
		return nil, fmt.Errorf("marshal value: %w", err)
	}
	return &sarama.ProducerMessage{
		Topic: topic,
		Key:   sarama.ByteEncoder(keyBytes),
		Value: sarama.ByteEncoder(valueBytes),
	}, nil
}

// generateOrder builds a single mock order stamped with the current time.
func generateOrder(rng *rand.Rand, orderID int) Order {
	quantity := rng.Intn(5) + 1
	unitPrice := float64(5+rng.Intn(495)) + rng.Float64()

	return Order{
		OrderID:    orderID,
		CustomerID: rng.Intn(1000) + 1,
		Product:    products[rng.Intn(len(products))],
		Quantity:   quantity,
		Amount:     float64(quantity) * unitPrice,
		Status:     statuses[rng.Intn(len(statuses))],
		OrderDate:  time.Now().UTC().Format(time.RFC3339),
	}
}

func main() {
	log.Println("Starting live-orders producer...")

	brokerAddress := mustGetenv("KAFKA_SERVICE_URI")
	username := mustGetenv("KAFKA_USERNAME")
	password := mustGetenv("KAFKA_PASSWORD")
	topic := getenvDefault("KAFKA_TOPIC", "order")

	ordersPerMinute := 100
	if v := os.Getenv("ORDERS_PER_MINUTE"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n <= 0 {
			log.Fatalf("ORDERS_PER_MINUTE must be a positive integer, got %q", v)
		}
		ordersPerMinute = n
	}
	interval := intervalFor(ordersPerMinute)
	log.Printf("Config: topic=%q rate=%d orders/min (1 every %s)", topic, ordersPerMinute, interval)

	config := sarama.NewConfig()
	config.Producer.Return.Successes = true

	// TLS with an empty config uses the system root CA pool, which already trusts
	// the Let's Encrypt CA serving the broker's SASL_SSL listener. No project CA
	// or client certificate/key needed.
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = &tls.Config{}

	// SASL authentication over TLS (SASL_SSL) using SCRAM-SHA-512.
	config.Net.SASL.Enable = true
	config.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA512
	config.Net.SASL.User = username
	config.Net.SASL.Password = password
	config.Net.SASL.SCRAMClientGeneratorFunc = func() sarama.SCRAMClient {
		return &XDGSCRAMClient{HashGeneratorFcn: SHA512}
	}

	producer, err := sarama.NewSyncProducer([]string{brokerAddress}, config)
	if err != nil {
		log.Fatalf("Failed to create Kafka producer: %v", err)
	}
	defer producer.Close()

	// Cancel the loop on SIGINT/SIGTERM so Aiven Apps can stop us cleanly.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	var sent int
	orderID := 1
	log.Println("Streaming live orders. Press Ctrl-C (or send SIGTERM) to stop.")

	for {
		select {
		case <-ctx.Done():
			log.Printf("Shutdown signal received. Sent %d orders. Closing producer...", sent)
			return
		case <-ticker.C:
			order := generateOrder(rng, orderID)

			msg, err := newOrderMessage(topic, order)
			if err != nil {
				log.Printf("Failed to build message for order %d: %v", order.OrderID, err)
				continue
			}

			partition, offset, err := producer.SendMessage(msg)
			if err != nil {
				// Log and keep going — a transient broker hiccup shouldn't kill
				// a long-running producer.
				log.Printf("Failed to send order %d: %v", order.OrderID, err)
				continue
			}

			sent++
			orderID++
			if sent%50 == 0 {
				log.Printf("Sent %d orders (latest: order %d → partition %d offset %d)", sent, order.OrderID, partition, offset)
			}
		}
	}
}
