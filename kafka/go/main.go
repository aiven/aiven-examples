// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

package main

import (
	"flag"
	"log"
)

func main() {
	var args = parseArgs()
	if args.Consumer {
		kafkaConsumerExample(args)
	} else if args.Producer {
		kafkaProducerExample(args)
	}
}

type Args struct {
	ServiceURI string
	CaPath     string
	KeyPath    string
	CertPath   string
	Consumer   bool
	Producer   bool
}

func parseArgs() Args {
	var args Args
	flag.StringVar(&args.ServiceURI, "service-uri", "", "Service URI in the form host:port")
	flag.StringVar(&args.CaPath, "ca-path", "", "Path to project CA certificate")
	flag.StringVar(&args.KeyPath, "key-path", "", "Path to the Kafka Access Key (obtained from Aiven Console)")
	flag.StringVar(&args.CertPath, "cert-path", "", "Path to the Kafka Certificate Key (obtained from Aiven Console)")
	flag.BoolVar(&args.Consumer, "consumer", false, "Run Kafka consumer example")
	flag.BoolVar(&args.Producer, "producer", false, "Run Kafka producer example")

	flag.Parse()
	if args.ServiceURI == "" {
		fail("-service-uri is required")
	} else if args.CaPath == "" {
		fail("-ca-path is required")
	} else if args.KeyPath == "" {
		fail("-key-path is required")
	} else if args.CertPath == "" {
		fail("-cert-path is required")
	} else if args.Consumer && args.Producer {
		fail("-consumer and -producer are mutually exclusive")
	} else if !args.Consumer && !args.Producer {
		fail("-producer or -consumer must be specified")
	}
	return args
}

func fail(message string) {
	flag.Usage()
	log.Fatal(message)
}
