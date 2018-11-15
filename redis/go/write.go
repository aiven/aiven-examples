// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"crypto/tls"
	"log"

	"github.com/go-redis/redis"
)

func main() {
	client := redis.NewClient(&redis.Options{
		Addr:     "redis-3b8d4ed6-myfirstcloudhub.aivencloud.com:15194",
		Password: "nr0dfnswz36xs9pi",
		DB:       0,
		TLSConfig: &tls.Config{
			ServerName: "redis-3b8d4ed6-myfirstcloudhub.aivencloud.com",
		},
	})
	_, err := client.Ping().Result()
	if err != nil {
		log.Fatal(err)
	}
	err = client.Set("foo", "bar", 0).Err()
	if err != nil {
		log.Fatal(err)
	}
}
