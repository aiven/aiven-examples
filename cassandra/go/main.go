// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

package main

import (
	"flag"
	"log"
)

func main() {
	var args = parseArgs()
	cassandraExample(args)
}

type Args struct {
	Host     string
	Port     int
	Username string
	Password string
	CaPath   string
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.Host, "host", "", "Cassandra host")
	flag.IntVar(&args.Port, "port", -1, "Cassandra port")
	flag.StringVar(&args.Username, "username", "avnadmin", "Cassandra username")
	flag.StringVar(&args.Password, "password", "", "Cassandra password")
	flag.StringVar(&args.CaPath, "ca-path", "./ca.pem", "Path to project CA certificate")
	flag.Parse()

	if args.Host == "" {
		fail("-host is required")
	} else if args.Port == -1 {
		fail("-port is required")
	} else if args.Password == "" {
		fail("-password is required")
	}
	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
