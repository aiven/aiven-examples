package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strconv"
	"time"

	"github.com/IBM/sarama"
)

type Product struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

// generateMockProducts creates a specified number of mock product instances
func generateMockProducts(count int) []Product {
	log.Printf("Generating %d mock products", count)
	products := make([]Product, count)

	// Initialize random number generator with a seed
	rand := rand.New(rand.NewSource(time.Now().UnixNano()))

	for i := 0; i < count; i++ {
		id := strconv.Itoa(i + 1)
		products[i] = Product{
			ID:    id,
			Name:  fmt.Sprintf("Product %s", id),
			Price: float64(5+rand.Intn(95)) + rand.Float64(), // Random price between 5.0 and 100.0
		}
		log.Printf("Generated product: %+v", products[i])
	}

	return products
}

func main() {
	log.Println("Starting Kafka producer...")
	// Set up TLS configuration for Aiven Kafka

	// File paths for Aiven cert files
	certFile := "<path-to-your-cert-file>"
	keyFile := "<path-to-your-key-file>"
	caFile := "<path-to-your-ca-file>"

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatalf("Failed to load client certificate/key ('%s', '%s'): %v", certFile, keyFile, err)
	}
	log.Printf("Loaded client certificate from '%s' and key from '%s'.\n", certFile, keyFile)

	caCert, err := os.ReadFile(caFile) // Changed from ioutil.ReadFile
	if err != nil {
		log.Fatalf("Failed to read CA certificate from '%s': %v", caFile, err)
	}
	log.Printf("Loaded CA certificate from '%s'.\n", caFile)

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		log.Fatalf("Failed to append CA certificate")
	}
	log.Println("Appended CA certificate to pool.")

	tlsConfig := &tls.Config{
		Certificates:       []tls.Certificate{cert},
		RootCAs:            caCertPool,
		InsecureSkipVerify: false, // This should be false for production against Aiven
	}

	config := sarama.NewConfig()
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsConfig
	config.Producer.Return.Successes = true

	// Broker addresses for Aiven Kafka
	brokers := []string{"<your-kafka-broker-address>"}

	log.Printf("Connecting to Kafka brokers: %v", brokers)
	producer, err := sarama.NewSyncProducer(brokers, config)
	if err != nil {
		log.Fatalf("Failed to create Kafka producer: %v", err)
	}
	defer func() {
		log.Println("Closing Kafka producer.")
		if err := producer.Close(); err != nil {
			log.Printf("Error closing Kafka producer: %v", err)
		}
	}()

	// Generate mock products (e.g., 5 products)
	mockProducts := generateMockProducts(15)

	log.Printf("Attempting to send %d products to topic 'product'...", len(mockProducts))
	// Send each product to Kafka
	for _, product := range mockProducts {
		productBytes, err := json.Marshal(product)
		if err != nil {
			// This is a local error, probably indicates a bug in Product struct or json marshaling
			log.Fatalf("Failed to marshal product %+v: %v", product, err)
		}

		msg := &sarama.ProducerMessage{
			Topic: "product", // Ensure this topic exists or auto-creation is enabled on broker
			Value: sarama.ByteEncoder(productBytes),
			// Key: sarama.StringEncoder(product.ID), // Optional: If you want to set a message key
		}
		partition, offset, err := producer.SendMessage(msg)
		if err != nil {
			// This error is from Kafka (e.g., network issue, topic issue, broker issue)
			log.Fatalf("Failed to send message for product ID %s to Kafka: %v", product.ID, err)
		}

		log.Printf("Product %s (Name: %s) sent to partition %d at offset %d", product.ID, product.Name, partition, offset)
	}
	log.Println("All products sent successfully.")
}
