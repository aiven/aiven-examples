package main

import (
	"log"

	"github.com/gocql/gocql"
)

const (
	host     = "cassandra-3b8d4ed6-myfirstcloudhub.aivencloud.com"
	port     = 15193
	username = "avnadmin"
	password = "<your password here>"
)

// *******
// DISCLAIMER: This code might fail because of "unable to connect to initial hosts: unexpected authenticator"
// We have an open pull request at github.com/gocql/gocql for them to add the Aiven authenticator to the approved list
// ********

// Create a keyspace called 'example_keyspace' before running this

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
	if err := session.Query(
		"CREATE TABLE example_table (id int PRIMARY KEY, message text)",
	).Exec(); err != nil {
		log.Print(err)
	}
	if err := session.Query(
		"INSERT INTO example_table (id, message) VALUES (?, ?)", 123, "Hello world!",
	).Exec(); err != nil {
		log.Fatal(err)
	}
	log.Println("Row inserted")
}
