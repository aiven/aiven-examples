// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"

	"github.com/Shopify/sarama"
)

var kafkaURI = "kafka-example.avns.net:11111"

func main() {
	client, err := kafkaClient()
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()
	producer, err := sarama.NewSyncProducerFromClient(client)
	if err != nil {
		log.Fatal(err)
	}
	defer producer.Close()
	for i := 1; i <= 5; i++ {
		partition, offset, err := producer.SendMessage(&sarama.ProducerMessage{
			Topic: "my_topic",
			Value: sarama.StringEncoder(fmt.Sprintf("Testing %d", i)),
		})
		if err != nil {
			log.Fatalf("Could not send message: %v", err)
		}
		log.Printf("Message 'Testing %d' sent, partition: %d, offset: %d\n", i, partition, offset)
	}
}

func kafkaClient() (sarama.Client, error) {
	tlsCfg, err := tlsConfig()
	if err != nil {
		return nil, err
	}
	config := sarama.NewConfig()
	config.Producer.Return.Successes = true
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsCfg
	config.Version = sarama.V0_10_2_0
	client, err := sarama.NewClient([]string{kafkaURI}, config)
	if err != nil {
		return nil, err
	}
	return client, nil
}

func tlsConfig() (*tls.Config, error) {
	keypair, err := tls.LoadX509KeyPair("service.cert", "service.key")
	if err != nil {
		return nil, err
	}
	caCert, err := ioutil.ReadFile("ca.pem")
	if err != nil {
		return nil, err
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{keypair},
		RootCAs:      caCertPool,
	}
	return tlsCfg, nil
}
