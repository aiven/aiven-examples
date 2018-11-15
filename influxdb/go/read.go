// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"fmt"
	"log"

	"github.com/influxdata/influxdb/client/v2"
)

const (
	host     = "https://influx-3b8d4ed6-myfirstcloudhub.aivencloud.com:15193"
	username = "avnadmin"
	password = "nr0dfnswz36xs9pi"
	database = "defaultdb"
)

func main() {
	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     host,
		Username: username,
		Password: password,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer c.Close()
	q := client.Query{
		Command:  "select value from cpu_load_short;",
		Database: database,
	}
	response, err := c.Query(q)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(response.Results)
}
