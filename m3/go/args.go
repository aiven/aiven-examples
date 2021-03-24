// Copyright (c) 2021 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"flag"
	"log"
)

type Args struct {
	Address    string
	MetricName string
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.Address, "address", "", "M3db address")
	flag.StringVar(&args.MetricName, "metric-name", "", "Metric name")
	flag.Parse()

	if args.Address == "" {
		fail("-address is required")
	}
	if args.MetricName == "" {
		fail("-metric-name is required")
	}
	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
