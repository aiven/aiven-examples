package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/coreos/pkg/flagutil"
	"github.com/dghubble/go-twitter/twitter"
	"github.com/dghubble/oauth1"
	"github.com/spf13/viper"
)

func streamRunner(stream *twitter.Stream) {
	kProd := ConnectKafka()
	demux := twitter.NewSwitchDemux()
	demux.Tweet = func(msg *twitter.Tweet) {
//		if msg.Coordinates != nil {
			key := []byte(msg.IDStr)
			tweetBytes := new(bytes.Buffer)
			json.NewEncoder(tweetBytes).Encode(msg)
			fmt.Println(msg.Text)
			if msg.FullText != "" {
				fmt.Println(msg.FullText)
			}
			fmt.Println("----")
			value := tweetBytes.Bytes()
			tweetBytes.Bytes()

			go WriteMessage(kProd, key, value)
		//}
	}
	fmt.Println("Stream started")

	for message := range stream.Messages {
    fmt.Println(message)
		demux.Handle(message)
	}
}

func main() {
	flags := struct {
		consumerKey    string
		consumerSecret string
		accessToken    string
		accessSecret   string
	}{}

	loadConfig()
	fmt.Println(viper.GetString("consumerKey"))
	fmt.Println(viper.GetString("kafkaURI"))
	flag.StringVar(&flags.consumerKey, "consumer-key", viper.GetString("consumerKey"), "Twitter Consumer Key")
	flag.StringVar(&flags.consumerSecret, "consumer-secret", viper.GetString("consumerSecret"), "Twitter Consumer Secret")
	flag.StringVar(&flags.accessToken, "access-token", viper.GetString("accessToken"), "Twitter Access Token")
	flag.StringVar(&flags.accessSecret, "access-secret", viper.GetString("accessSecret"), "Twitter Access Secret")
	flag.Parse()
	flagutil.SetFlagsFromEnv(flag.CommandLine, "TWITTER")

	if flags.consumerKey == "" || flags.consumerSecret == "" {
		log.Fatal("Application Access Token required")
	}
	config := oauth1.NewConfig(flags.consumerKey, flags.consumerSecret)
	token := oauth1.NewToken(flags.accessToken, flags.accessSecret)
	httpClient := config.Client(oauth1.NoContext, token)

	// Twitter Client
	client := twitter.NewClient(httpClient)

	filterParams := &twitter.StreamFilterParams{
		Track: []string{"Trump", "Brexit", "Travel"},
	}
	stream, err := client.Streams.Filter(filterParams)
	if err != nil {
		fmt.Errorf("Failed to open stream: %s", err)
	}
	go streamRunner(stream)
	ch := make(chan os.Signal)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	log.Println(<-ch)

	fmt.Println("Stopping Stream...")
	stream.Stop()
}
