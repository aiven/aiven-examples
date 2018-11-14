// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"fmt"
	"github.com/influxdata/influxdb1-client/v2"
	"log"
	"time"
)

func influxdbExample(args Args) {
	httpClient, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     args.Host,
		Username: args.Username,
		Password: args.Password,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer httpClient.Close()

	writeData(args, httpClient)
	readData(args, httpClient)
}

func writeData(args Args, httpClient client.Client) {
	// Create a new point batch
	bp, err := client.NewBatchPoints(client.BatchPointsConfig{
		Database:  args.Database,
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
	if err := httpClient.Write(bp); err != nil {
		log.Fatal(err)
	}
}

func readData(args Args, httpClient client.Client) {
	q := client.Query{
		Command:  "select value from cpu_load_short;",
		Database: args.Database,
	}
	response, err := httpClient.Query(q)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(response.Results)
}
