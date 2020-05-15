package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"

	"github.com/spf13/viper"
)

func loadCerts() tls.Config {
	keypair, err := tls.LoadX509KeyPair("./service.cert", "./service.key")
	if err != nil {
		fmt.Println(err)
	}

	caCert, err := ioutil.ReadFile("./ca.pem")
	if err != nil {
		log.Fatalf("Failed to read CA Certificate file: %s", err)
	}

	caCertPool := x509.NewCertPool()
	ok := caCertPool.AppendCertsFromPEM(caCert)
	if !ok {
		log.Fatalf("Failed to parse CA Certificate file: %s", err)
	}
	return tls.Config{Certificates: []tls.Certificate{keypair}, RootCAs: caCertPool}
}

func loadConfig() {
	viper.SetConfigType("yaml")
	viper.AddConfigPath("./")
	viper.SetConfigName("config.yaml")
	err := viper.ReadInConfig() // Find and read the config file
	if err != nil {             // Handle errors reading the config file
		panic(fmt.Errorf("Fatal error config file: %s", err))
	}
}
