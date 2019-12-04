// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"database/sql"
	"flag"
	"fmt"
	_ "github.com/lib/pq"
	"log"
)

func main() {

	serviceURI := flag.String("service-uri", "", "Postgres Service URI (obtained from Aiven console)")
	flag.Parse()
	if *serviceURI == "" {
		flag.Usage()
		log.Fatal("-service-uri is required")
	}

	// Connect to Postgres DB
	db, err := sql.Open("postgres", *serviceURI)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Ensure we can communicate successfully
	err = db.Ping()
	if err != nil {
		panic(err)
	}

	// Perform a query
	rows, err := db.Query("SELECT current_database()")
	if err != nil {
		panic(err)
	}
	for rows.Next() {
		var result string
		err = rows.Scan(&result)
		if err != nil {
			panic(err)
		}
		fmt.Printf("Successfully connected to: %s\n", result)
	}
}
