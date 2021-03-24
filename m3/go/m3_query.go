// Copyright (c) 2021 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"fmt"
	"log"
	"time"

	"io/ioutil"
	"net/http"
)

func main() {
	var args = parseArgs()
	now := time.Now().Unix()
	// Query metrics from a one hour range
	queryURL := fmt.Sprintf("%s/api/v1/query_range?query=%s&start=%d&end=%d&step=60",
		args.Address, args.MetricName, now-3600, now,
	)
	resp, err := http.Get(queryURL)
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("%s: %s\n", resp.Status, body)
}
