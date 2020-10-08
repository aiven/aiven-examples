// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"flag"
	"log"
  "strings"
)

func main() {
	var args = parseArgs()
	if strings.ToLower(args.Example) == "person" {
		PersonIndexExample(args)
	} else if strings.ToLower(args.Example) == "reddit" {
		CommentIndexExample(args)
	} else {
    fail("Example provided is not supported")
  }
}

type Args struct {
	URL      string
	Username string
	Password string
	Example string
  DB string
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.URL, "url", "", "Elasticsearch URL in the form host:port")
	flag.StringVar(&args.Username, "username", "avnadmin", "Elasticsearch username")
	flag.StringVar(&args.Password, "password", "", "Elasticsearch password")
	flag.StringVar(&args.Example, "example", "Person", "Example you want to run (Person, Reddit)")
	flag.StringVar(&args.DB, "SQLite file path for Reddit example", "", "Location to Reddit SQLite database containing May2015 dataset")
	flag.Parse()

	if args.URL == "" {
		fail("-url is required")
	}
  if args.Password == "" {
		fail("-password is required")
	}
  if args.DB == "" && args.Example == "Reddit" {
    fail("-DB is required")
  }


	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
