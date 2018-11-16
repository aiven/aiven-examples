// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/olivere/elastic"
)

type person struct {
	Name      string    `json:"name"`
	Height    int       `json:"height"`
	Mass      int       `json:"mass"`
	BirthYear int       `json:"birth_year"`
	Gender    string    `json:"gender"`
	Created   time.Time `json:"created"`
	Edited    time.Time `json:"edited"`
}

func main() {
	client, err := elastic.NewClient(
		elastic.SetURL("https://es-3b8d4ed6-myfirstcloudhub.aivencloud.com:15193"),
		elastic.SetBasicAuth("avnadmin", "<your password here>"),
		elastic.SetSniff(false),
	)
	if err != nil {
		log.Fatal(err)
	}

	// Add a document to the index
	p := person{
		Name:      "John",
		Height:    185,
		Mass:      77,
		BirthYear: 1980,
		Gender:    "male",
		Created:   time.Now(),
		Edited:    time.Now(),
	}
	_, err = client.Index().
		Index("people").
		Type("people").
		Id("1").
		BodyJson(p).
		Do(context.Background())
	if err != nil {
		panic(err)
	}

	// Print the document we just added
	query := elastic.NewTermQuery("name", "john")
	searchResult, err := client.Search().
		Index("people").
		Query(query).
		Sort("name.keyword", true).
		From(0).Size(10).
		Pretty(true).
		Do(context.Background())
	if err != nil {
		panic(err)
	}
	for _, item := range searchResult.Hits.Hits {
		j, err := json.MarshalIndent(item.Source, "", "    ")
		if err != nil {
			panic(err)
		}
		fmt.Println(string(j))
	}
}
