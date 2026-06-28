package main

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/IBM/sarama"
)

// Kafka connection settings are read from environment variables:
//
//	KAFKA_SERVICE_URI - SASL_SSL broker address from the Aiven Console
//	                    (Service > Connection information, authentication "SASL").
//	                    NOTE: a different port than the certificate/mTLS endpoint,
//	                    e.g. kafka-iceberg-demo.a.aivencloud.com:12345
//	KAFKA_USERNAME    - Kafka SASL username (e.g. avnadmin)
//	KAFKA_PASSWORD    - Kafka SASL password
func mustGetenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return v
}

type OrderKey struct {
	KeyId   int    `json:"keyId"`
	KeyCode string `json:"keyCode"`
}

// Order represents an ecommerce order placed by a customer. This is the master
// data we stream in real time into the Iceberg data lake.
type Order struct {
	OrderID    int     `json:"orderId"`
	CustomerID int     `json:"customerId"`
	Product    string  `json:"product"`
	Quantity   int     `json:"quantity"`
	Amount     float64 `json:"amount"`
	Status     string  `json:"status"`    // PENDING, PAID, SHIPPED, DELIVERED, CANCELLED
	OrderDate  string  `json:"orderDate"` // RFC3339 timestamp
}

// generateMockOrders creates a specified number of mock ecommerce orders.
func generateMockOrders(count int) []Order {
	orders := make([]Order, count)
	rand := rand.New(rand.NewSource(time.Now().UnixNano()))

	products := []string{"Laptop", "Headphones", "Keyboard", "Monitor", "Webcam", "Mouse", "Desk Chair", "USB-C Cable"}
	statuses := []string{"PENDING", "PAID", "SHIPPED", "DELIVERED", "CANCELLED"}

	for i := 0; i < count; i++ {
		quantity := rand.Intn(5) + 1
		unitPrice := float64(5+rand.Intn(495)) + rand.Float64()

		orders[i] = Order{
			OrderID:    i + 1,
			CustomerID: rand.Intn(1000) + 1,
			Product:    products[rand.Intn(len(products))],
			Quantity:   quantity,
			Amount:     float64(quantity) * unitPrice,
			Status:     statuses[rand.Intn(len(statuses))],
			OrderDate:  time.Now().Add(-time.Duration(rand.Intn(720)) * time.Hour).Format(time.RFC3339),
		}
	}

	return orders
}

func main() {
	log.Println("Starting Kafka producer...")

	brokerAddress := mustGetenv("KAFKA_SERVICE_URI")
	username := mustGetenv("KAFKA_USERNAME")
	password := mustGetenv("KAFKA_PASSWORD")

	config := sarama.NewConfig()
	config.Producer.Return.Successes = true

	// TLS with an empty config uses the system root CA pool, which already trusts
	// the Let's Encrypt CA serving the broker's SASL_SSL listener. No project CA
	// (ca.pem) or client certificate/key needed.
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

	brokers := []string{brokerAddress}

	producer, err := sarama.NewSyncProducer(brokers, config)
	if err != nil {
		log.Fatalf("Failed to create Kafka producer: %v", err)
	}
	defer producer.Close()

	// Generate mock orders
	mockOrders := generateMockOrders(15)

	// Send each order to Kafka with a key
	for _, order := range mockOrders {
		// Create a key for the message
		key := OrderKey{
			KeyId:   order.OrderID * 10, // Example key ID generation
			KeyCode: fmt.Sprintf("O%d", order.OrderID),
		}

		keyBytes, err := json.Marshal(key)
		if err != nil {
			log.Fatalf("Failed to marshal key: %v", err)
		}

		valueBytes, err := json.Marshal(order)
		if err != nil {
			log.Fatalf("Failed to marshal order: %v", err)
		}

		msg := &sarama.ProducerMessage{
			Topic: "order",
			Key:   sarama.ByteEncoder(keyBytes),
			Value: sarama.ByteEncoder(valueBytes),
		}

		partition, offset, err := producer.SendMessage(msg)
		if err != nil {
			log.Fatalf("Failed to send message: %v", err)
		}

		log.Printf("Sent order %d to partition %d at offset %d", order.OrderID, partition, offset)
	}

	log.Println("All orders sent successfully.")
}
