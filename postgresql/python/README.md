### PostgreSQL Python Example

This example uses the [pq](psycopg2) library to connect to PostgreSQL and perform a simple query.
#### Installing Dependencies  

```
pip install psycopg2-binary
```

#### Running The Example
Note: You can retrieve the Service URI from the Aiven Console overview tab.
```
go run main.go --service-uri postgres://<user>:<password>@<host>:<port>/<database>?<options>
```