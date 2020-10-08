// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"context"
	// "encoding/json"
	_ "database/sql"
	_ "github.com/mattn/go-sqlite3"
	"fmt"
	"github.com/olivere/elastic/v7"
	"github.com/jmoiron/sqlx"
	"log"
	"time"
	"strconv"
	
)

type Comment struct {
	ID    string       `json:"id"`
	Author      string    `json:"author"`
	ParentID      string       `json:"parent_id" db:"parent_id"`
	Body string       `json:"body"`
	Subreddit    string    `json:"subreddit"`
	Created   string `json:"created_utc" db:"created_utc"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

// Dataset source: https://www.kaggle.com/reddit/reddit-comments-may-2015

func CommentIndexExample(args Args) {
	client, err := elastic.NewClient(
		elastic.SetURL(args.URL),
		elastic.SetBasicAuth(args.Username, args.Password),
		elastic.SetSniff(false),
	)
	if err != nil {
		log.Fatal(err)
	}
	db, err := sqlx.Open("sqlite3", args.DB)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	
	commentTblGet := `select author, id, parent_id, body, subreddit, created_utc from May2015;`
	rows, err := db.Queryx(commentTblGet)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		c := Comment{}
		err = rows.StructScan(&c)
		
		i, err := strconv.ParseInt(c.Created, 10, 64)
		if err != nil {
			panic(err)
		}
		c.CreatedAt = time.Unix(i, 0)
		_, err = client.Index().
			Index("reddit_comments").
			Id(c.ID).
			BodyJson(c).
			Do(context.Background())
		if err != nil {
			panic(err)
		} else {
			fmt.Println("Inserted ", c.ID)
		}
	}

}
