package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"github.com/Shopify/sarama"
	"io/ioutil"
)

func kafkaClient(args Args) (sarama.Client, error) {
	tlsCfg, err := tlsConfig(args.CertPath, args.KeyPath, args.CaPath)
	if err != nil {
		return nil, err
	}
	config := sarama.NewConfig()
	config.Producer.Return.Successes = true
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsCfg
	config.Version = sarama.V0_10_2_0
	client, err := sarama.NewClient([]string{args.ServiceURI}, config)
	if err != nil {
		fmt.Println(args.ServiceURI, config)
		panic(err)
		return nil, err
	}
	return client, nil
}

func tlsConfig(certPath, keyPath, caPath string) (*tls.Config, error) {
	keypair, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		return nil, err
	}
	caCert, err := ioutil.ReadFile(caPath)
	if err != nil {
		return nil, err
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{keypair},
		RootCAs:      caCertPool,
	}
	return tlsCfg, nil
}
