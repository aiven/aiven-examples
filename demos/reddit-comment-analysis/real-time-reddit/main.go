package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
	"os/signal"
	"syscall"

	//"github.com/turnage/graw/reddit"
	"github.com/Shopify/sarama"
	"github.com/vartanbeno/go-reddit/reddit"
	"github.com/joho/godotenv"
)

func kafkaConnect() sarama.SyncProducer {
	caCert, err := ioutil.ReadFile(os.Getenv("CA_PATH"))
	if err != nil {
		panic(err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsConfig := &tls.Config{
		RootCAs: caCertPool,
	}

	// parse Kafka cluster version
	version, err := sarama.ParseKafkaVersion("2.6.0")
	if err != nil {
		panic(err)
	}

	// init config, enable errors and notifications
	config := sarama.NewConfig()
	config.Version = version
	config.Metadata.Full = true
	config.ClientID = "aiven-sasl-client-plain"
	config.Producer.Return.Successes = true

	// Kafka SASL configuration
	config.Net.SASL.Enable = true
	config.Net.SASL.User = os.Getenv("KAFKA_USER")
	config.Net.SASL.Password = os.Getenv("KAFKA_PWD")
	config.Net.SASL.Handshake = true
	config.Net.SASL.Mechanism = sarama.SASLTypePlaintext

	// TLS configuration
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsConfig


	// init producer
	brokers := []string{os.Getenv("KAFKA_URL")}
	producer, err := sarama.NewSyncProducer(brokers, config)
	if err != nil {
		panic(err)
	}
	return producer
}

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("Error loading .env file")
	}
	ctx := context.Background()
  // Currently unused but would be to allow multi process comms or stream interruption
	sig := make(chan os.Signal, 1)
	defer close(sig)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	prod := kafkaConnect()
	httpClient := &http.Client{Timeout: time.Second * 30}
	client, _ := reddit.NewClient(httpClient, &reddit.Credentials{
		ID:       os.Getenv("APP_ID"),
		Secret:   os.Getenv("APP_SECRET"),
		Username: os.Getenv("REDDIT_USERNAME"),
		Password: os.Getenv("REDDIT_PASSWORD"),
	})

	posts, _, err := client.Subreddit.TopPosts(ctx, os.Getenv("SUBREDDIT"), &reddit.ListPostOptions{
		ListOptions: reddit.ListOptions{
			Limit: 100,
		},
		Time: "all",
	})
	for _, post := range posts.Posts {
		pnc, _, err := client.Post.Get(ctx, post.ID)
		if err != nil {
			log.Fatal(err)
		}
		for _, cmt := range (pnc.Comments) {
			jsonMsg, _ := json.Marshal(cmt)

			prod.SendMessage(&sarama.ProducerMessage{
				Topic: "reddit-real-time-comments", Key: sarama.StringEncoder(cmt.ID),
				Value: sarama.ByteEncoder(jsonMsg),
			})
			fmt.Println("Posted")
		}
	}
	prod.Close()
}
