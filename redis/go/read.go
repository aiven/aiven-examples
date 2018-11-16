// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"crypto/tls"
	"fmt"
	"log"

	"github.com/go-redis/redis"
)

func main() {
	client := redis.NewClient(&redis.Options{
		Addr:     "redis-3b8d4ed6-myfirstcloudhub.aivencloud.com:15194",
		Password: "<your password here>",
		DB:       0,
		TLSConfig: &tls.Config{
			ServerName: "redis-3b8d4ed6-myfirstcloudhub.aivencloud.com",
		},
	})
	_, err := client.Ping().Result()
	if err != nil {
		log.Fatal(err)
	}
	val, err := client.Get("foo").Result()
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(val)
}
