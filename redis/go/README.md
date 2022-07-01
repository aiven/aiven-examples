### Redis®* Go Example

This example uses the [redis](https://github.com/go-redis/redis) library to connect to Redis®*, write a key/value pair, and read it out again.

#### Installing Dependencies  

```
go get github.com/go-redis/redis
```

### Compiling The Example Program

```
go build main.go redis_example.go
```

#### Running The Example
Note: You can retrieve the connection details from the Aiven Console overview tab.
```
./main -host <redis host> -password <redis password> -port <redis port>
```

#### Trademark
\* Redis is a registered trademark of Redis Ltd. Any rights therein are reserved to Redis Ltd. Any use by Aiven Oy is for referential purposes only and does not indicate any sponsorship, endorsement or affiliation between Redis and Aiven Oy.