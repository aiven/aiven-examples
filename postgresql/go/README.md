### PostgreSQL Go Example

This example uses the [pq](https://github.com/lib/pq) library to connect to PostgreSQL and perform a simple query.
#### Installing Dependencies  

```
go get github.com/lib/pq
```

#### Running The Example
Note: You can retrieve the Service URI from the Aiven Console overview tab.
```
go run main.go -service-uri postgres://<user>:<password>@<host>:<port>/<database>?<options>
```
