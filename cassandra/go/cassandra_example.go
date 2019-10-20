// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

package main

import (
	"fmt"
	"github.com/gocql/gocql"
	"log"
	"time"
)

func cassandraExample(args Args) {
	var session = createSession(args)
	defer session.Close()
	createSchema(session)
	writeData(session)
	readData(session)
}

func createSession(args Args) gocql.Session {
	cluster := gocql.NewCluster(args.Host)
	cluster.ConnectTimeout = 10 * time.Second
	cluster.Port = args.Port
	cluster.ProtoVersion = 4
	cluster.Authenticator = gocql.PasswordAuthenticator{
		Username: args.Username,
		Password: args.Password,
	}
	cluster.SslOpts = &gocql.SslOptions{
		CaPath: args.CaPath,
	}
	cluster.Consistency = gocql.Quorum

	session, err := cluster.CreateSession()
	if err != nil {
		log.Fatal(err)
	}
	return *session
}

func createSchema(session gocql.Session) {
	if err := session.Query(
		"CREATE KEYSPACE IF NOT EXISTS example_keyspace WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'aiven': 3}",
	).Exec(); err != nil {
		log.Fatal(err)
	}
	if err := session.Query(
		"CREATE TABLE IF NOT EXISTS example_keyspace.example_go (id int PRIMARY KEY, message text)",
	).Exec(); err != nil {
		log.Fatal(err)
	}
}

func writeData(session gocql.Session) {
	for i := 1; i <= 10; i++ {
		if err := session.Query(
			"INSERT INTO example_keyspace.example_go (id, message) VALUES (?, ?)", i, "Hello from golang!",
		).Exec(); err != nil {
			log.Fatal(err)
		}
	}
}

func readData(session gocql.Session) {
	iter := session.Query("SELECT id, message FROM example_keyspace.example_go").Iter()
	var id int
	var message string
	for iter.Scan(&id, &message) {
		fmt.Printf("Row: id = %d, message = %s\n", id, message)
	}
	if err := iter.Close(); err != nil {
		log.Fatal(err)
	}
}
