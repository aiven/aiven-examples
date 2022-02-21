### Redis Ruby Example

This example uses the [redis](https://pypi.org/project/redis/) library to connect to Redis, write a key/value pair, and read it out again.

#### Installing Dependencies  
Use [bundler]() to install the dependencies in the example `Gemfile`:
```
bundle install
```

#### Running The Example
Note: You can retrieve the connection details from the Aiven Console overview tab.

You can run the example using either the service URL:
```
ruby example.rb --url <redis service url>
```

Or the host, port and password:
```
ruby example.rb --host <redis host> --port <redis port> --password <redis password>
```
