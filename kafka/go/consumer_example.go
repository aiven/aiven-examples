// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"context"
	"fmt"
	"github.com/Shopify/sarama"
	"log"
)

func kafkaConsumerExample(args Args) {
	client, err := kafkaClient(args)
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
		topics := []string{"go_example_topic"}
		handler := exampleConsumerGroupHandler{}
		err := group.Consume(ctx, topics, handler)
		if err != nil {
			log.Fatal(err)
		}
	}
}

type exampleConsumerGroupHandler struct{}

func (exampleConsumerGroupHandler) Setup(sarama.ConsumerGroupSession) error {
	return nil
}
func (exampleConsumerGroupHandler) Cleanup(sarama.ConsumerGroupSession) error {
	return nil
}

func (h exampleConsumerGroupHandler) ConsumeClaim(sess sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	log.Println("Ready to consume messages")
	for msg := range claim.Messages() {
		fmt.Printf("Message topic:%q partition:%d offset:%d, message: %q\n", msg.Topic, msg.Partition, msg.Offset, msg.Value)
		sess.MarkMessage(msg, "")
	}
	return nil
}
