package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/IBM/sarama"
)

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

	// Set up TLS configuration
	certFile := "./certs/service.cert"
	keyFile := "./certs/service.key"
	caFile := "./certs/ca.pem"

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatalf("Failed to load client certificate/key: %v", err)
	}

	caCert, err := os.ReadFile(caFile)
	if err != nil {
		log.Fatalf("Failed to read CA certificate: %v", err)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		log.Fatalf("Failed to append CA certificate")
	}

	tlsConfig := &tls.Config{
		Certificates:       []tls.Certificate{cert},
		RootCAs:            caCertPool,
		InsecureSkipVerify: false,
	}

	config := sarama.NewConfig()
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsConfig
	config.Producer.Return.Successes = true

	brokers := []string{KafkaBrokerAddress}

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
