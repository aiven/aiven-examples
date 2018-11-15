// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"context"
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

	group, err := sarama.NewConsumerGroupFromClient("my-group", client)
	if err != nil {
		log.Fatal(err)
	}
	defer group.Close()

	ctx := context.Background()
	for {
		topics := []string{"my_topic"}
		handler := exampleConsumerGroupHandler{}

		err := group.Consume(ctx, topics, handler)
		if err != nil {
			log.Fatal(err)
		}
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
		fmt.Println(kafkaURI, config)
		panic(err)
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

type exampleConsumerGroupHandler struct{}

func (exampleConsumerGroupHandler) Setup(sarama.ConsumerGroupSession) error {
	return nil
}
func (exampleConsumerGroupHandler) Cleanup(sarama.ConsumerGroupSession) error {
	return nil
}

func (h exampleConsumerGroupHandler) ConsumeClaim(sess sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for msg := range claim.Messages() {
		fmt.Printf("Message topic:%q partition:%d offset:%d, message: %q\n", msg.Topic, msg.Partition, msg.Offset, msg.Value)
		sess.MarkMessage(msg, "")
	}
	return nil
}
