Kafka Streaming Twitter Producer

## Install

`go get github.com/aiven/aiven-examples/kafka/producers/twitter`

## Configuring

`cp config.yaml.example config.yaml`

* Register a Twitter application at [developer.twitter.com](https://developer.twitter.com)
* Set up a Kafka instance at [aiven.io](https://aiven.io)
* Add all keys and secrets  of the Twitter App to `config.yaml`
* Download Kafka Service `cert` and `key` to this directory
* Download CA `cert` to this directory
* Set the topics you want to monitor in `twitter_prod.go`

## Running

`go run *.go`

