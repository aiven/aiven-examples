// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

const (
	host     = "pg-3b8d4ed6-myfirstcloudhub.aivencloud.com"
	port     = 20985
	user     = "avnadmin"
	password = "<your password here>"
	dbname   = "defaultdb"
)

func main() {
	dbinfo := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=require",
		host, port, user, password, dbname)
	db, err := sql.Open("postgres", dbinfo)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	err = db.Ping()
	if err != nil {
		panic(err)
	}
	rows, err := db.Query("SELECT 1 = 1")
	if err != nil {
		panic(err)
	}
	for rows.Next() {
		var result bool
		err = rows.Scan(&result)
		if err != nil {
			panic(err)
		}
		fmt.Println(result)
	}
}
