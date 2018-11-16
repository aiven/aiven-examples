package main

import (
	"fmt"
	"log"

	"github.com/gocql/gocql"
)

// *******
// DISCLAIMER: This code might fail because of "unable to connect to initial hosts: unexpected authenticator"
// We have an open pull request at github.com/gocql/gocql for them to add the Aiven authenticator to the approved list
// ********

const (
	host     = "cassandra-3b8d4ed6-myfirstcloudhub.aivencloud.com"
	port     = 15193
	username = "avnadmin"
	password = "nr0dfnswz36xs9pi"
)

func main() {
	cluster := gocql.NewCluster(host)
	cluster.Port = port
	cluster.ProtoVersion = 4
	cluster.Authenticator = gocql.PasswordAuthenticator{
		Username: username,
		Password: password,
	}
	cluster.SslOpts = &gocql.SslOptions{
		CaPath: "ca.pem",
	}
	cluster.Keyspace = "example_keyspace"
	cluster.Consistency = gocql.Quorum
	session, err := cluster.CreateSession()
	if err != nil {
		log.Fatal(err)
	}
	defer session.Close()
	iter := session.Query("SELECT id, message FROM example_table").Iter()
	var id int
	var message string
	for iter.Scan(&id, &message) {
		fmt.Printf("Row: id = %d, message = %s\n", id, message)
	}
}
