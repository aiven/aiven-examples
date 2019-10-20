package main

import (
	"crypto/tls"
	"fmt"
	"github.com/go-redis/redis"
	"log"
)

func redisExample(host string, port int, password string) {
	client := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", host, port),
		Password: password,
		DB:       0,
		TLSConfig: &tls.Config{
			ServerName: host,
		},
	})

	_, err := client.Ping().Result()
	if err != nil {
		log.Fatal(err)
	}

    // Write our key/value pair
	err = client.Set("exampleKey", "exampleValue", 0).Err()
	if err != nil {
		log.Fatal(err)
	}

    // Read it out again
	val, err := client.Get("exampleKey").Result()
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("The value for 'exampleKey' is: ''%s'\n", val)
}
