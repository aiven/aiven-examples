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

type ProductKey struct {
	KeyId   int    `json:"keyId"`
	KeyCode string `json:"keyCode"`
}

type Product struct {
	ID       int     `json:"id"`
	Name     string  `json:"name"`
	Quantity int     `json:"quantity"`
	Price    float64 `json:"price"`
}

// generateMockProducts creates a specified number of mock product instances
func generateMockProducts(count int) []Product {
	products := make([]Product, count)
	rand := rand.New(rand.NewSource(time.Now().UnixNano()))

	for i := 0; i < count; i++ {
		products[i] = Product{
			ID:       i + 1,
			Name:     fmt.Sprintf("Product %d", i+1),
			Quantity: rand.Intn(100) + 1,
			Price:    float64(5+rand.Intn(95)) + rand.Float64(),
		}
	}

	return products
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

	// Generate mock products
	mockProducts := generateMockProducts(15)

	// Send each product to Kafka with a key
	for _, product := range mockProducts {
		// Create a key for the message
		key := ProductKey{
			KeyId:   product.ID * 10, // Example key ID generation
			KeyCode: fmt.Sprintf("P%d", product.ID),
		}

		keyBytes, err := json.Marshal(key)
		if err != nil {
			log.Fatalf("Failed to marshal key: %v", err)
		}

		valueBytes, err := json.Marshal(product)
		if err != nil {
			log.Fatalf("Failed to marshal product: %v", err)
		}

		msg := &sarama.ProducerMessage{
			Topic: "product",
			Key:   sarama.ByteEncoder(keyBytes),
			Value: sarama.ByteEncoder(valueBytes),
		}

		partition, offset, err := producer.SendMessage(msg)
		if err != nil {
			log.Fatalf("Failed to send message: %v", err)
		}

		log.Printf("Sent product %d to partition %d at offset %d", product.ID, partition, offset)
	}

	log.Println("All products sent successfully.")
}
