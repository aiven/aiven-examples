// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

package main

import (
	"flag"
	"log"
)

type Args struct {
	Host     string
	Port     int
	Password string
}

func main() {
	var args = parseArgs()
	redisExample(args.Host, args.Port, args.Password)
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.Host, "host", "", "Redis host")
	flag.IntVar(&args.Port, "port", -1, "Redis port")
	flag.StringVar(&args.Password, "password", "", "Redis password")
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
