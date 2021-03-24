all: m3_write m3_query

clean:
	rm -f m3_write m3_query

m3_write: m3_write.go args.go
	go build $^

m3_query: m3_query.go args.go
	go build $^

