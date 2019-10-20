// Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"gopkg.in/olivere/elastic.v6"
	"log"
	"math/rand"
	"strconv"
	"time"
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

func elasticIndexExample(args Args) {
	client, err := elastic.NewClient(
		elastic.SetURL(args.URL),
		elastic.SetBasicAuth(args.Username, args.Password),
		elastic.SetSniff(false),
	)
	if err != nil {
		log.Fatal(err)
	}

    // Generate a random id for our document
	var id = strconv.Itoa(rand.Intn(5000))

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
		Index("go_example").
		Type("people").
		Id(id).
		BodyJson(p).
		Do(context.Background())
	if err != nil {
		panic(err)
	}

	// Print the document we just added
	found, err := client.Get().
		Index("go_example").
		Id(id).
		Pretty(true).
		Do(context.Background())
	if err != nil {
		log.Fatal(err)
		panic(err)
	}
	j, err := json.MarshalIndent(found.Source, "", "  ")
	if err != nil {
		panic(err)
	}
	fmt.Println(string(j))
}
