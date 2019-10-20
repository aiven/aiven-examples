// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"fmt"
	"github.com/Shopify/sarama"
	"log"
)

func kafkaProducerExample(args Args) {
	client, err := kafkaClient(args)
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
