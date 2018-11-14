// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

package main

import (
	"flag"
	"log"
)

func main() {
	var args = parseArgs()
	influxdbExample(args)
}

type Args struct {
	Host     string
	Username string
	Password string
	Database string
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.Host, "host", "", "InfluxDB host")
	flag.StringVar(&args.Username, "username", "avnadmin", "InfluxDB username")
	flag.StringVar(&args.Password, "password", "", "InfluxDB password")
	flag.StringVar(&args.Database, "database", "defaultdb", "InfluxDB Database")
	flag.Parse()

	if args.Host == "" {
		fail("--host is required")
	} else if args.Password == "" {
		fail("--password is required")
	}
	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
