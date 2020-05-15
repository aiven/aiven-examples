package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/segmentio/kafka-go"
	"github.com/spf13/viper"
)

func ConnectKafka() *kafka.Writer {

	tlsconfig := loadCerts()
	dialer := &kafka.Dialer{
		Timeout:   10 * time.Second,
		DualStack: true,
		TLS:       &tlsconfig,
	}

	o := io.Writer(os.Stdout)
	l := log.New(o, "kfk", 0)

	w := kafka.NewWriter(kafka.WriterConfig{
		Brokers:     []string{viper.GetString("kafkaURI")},
		Topic:       viper.GetString("kafkaTopic"),
		Balancer:    &kafka.Hash{},
		Dialer:      dialer,
		ErrorLogger: l,
		Async:       false,
	})
	// defer w.Close()
	return w
}

func ConsumeKafka() *kafka.Reader {
	tlsconfig := loadCerts()
	dialer := &kafka.Dialer{
		Timeout:   10 * time.Second,
		DualStack: true,
		TLS:       &tlsconfig,
	}

	o := io.Writer(os.Stdout)
	l := log.New(o, "kfk", 0)

	r := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     []string{viper.GetString("kafkaURI")},
		Topic:       viper.GetString("kafkaTopic"),
		Dialer:      dialer,
		ErrorLogger: l,
	})
	// defer w.Close()
	return r
}

func WriteMessage(w *kafka.Writer, key []byte, val []byte) {
	err := w.WriteMessages(context.Background(), kafka.Message{Key: key, Value: val})
	if err != nil {
		fmt.Println(err)
		w.Close()
		w = ConnectKafka()
	}
}

