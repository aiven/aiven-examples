### Elasticsearch Go Example

This example uses the [elastic](https://github.com/olivere/elastic) library to connect to Elasticsearch, add a document, and read it out again.
#### Installing Dependencies  

```
go get gopkg.in/olivere/elastic.v6
```

### Compiling The Example Program

```
go build main.go elasticsearch_example.go
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./main --url https://<host>:<port> --password <Elasticsearch password>
```