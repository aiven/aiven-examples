// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"log"
	"time"

	"github.com/influxdata/influxdb/client/v2"
)

const (
	host     = "https://influx-3b8d4ed6-myfirstcloudhub.aivencloud.com:15193"
	username = "avnadmin"
	password = "<your password here>"
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

	// Create a new point batch
	bp, err := client.NewBatchPoints(client.BatchPointsConfig{
		Database:  database,
		Precision: "s",
	})
	if err != nil {
		log.Fatal(err)
	}

	// Create a point and add to batch
	tags := map[string]string{
		"host": "testnode",
	}
	fields := map[string]interface{}{
		"value": 0.95,
	}

	pt, err := client.NewPoint(
		"cpu_load_short",
		tags,
		fields,
		time.Now(),
	)

	if err != nil {
		log.Fatal(err)
	}
	bp.AddPoint(pt)
	if err := c.Write(bp); err != nil {
		log.Fatal(err)
	}

}
