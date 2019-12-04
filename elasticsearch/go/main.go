// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"flag"
	"log"
)

func main() {
	var args = parseArgs()
	elasticIndexExample(args)
}

type Args struct {
	URL      string
	Username string
	Password string
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.URL, "url", "", "Elasticsearch URL in the form host:port")
	flag.StringVar(&args.Username, "username", "avnadmin", "Elasticsearch username")
	flag.StringVar(&args.Password, "password", "", "Elasticsearch password")
	flag.Parse()

	if args.URL == "" {
		fail("-url is required")
	} else if args.Password == "" {
		fail("-password is required")
	}
	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
