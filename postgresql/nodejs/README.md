### PostgreSQL node.js Example

This example uses the [pq](https://www.npmjs.com/package/pg) library to connect to PostgreSQL and perform a simple query.
#### Installing Dependencies  

```
npm install
```

#### Running The Example

Retrieve the connection information from the Aiven Console overview tab. You will also need to download the CA Certificate; this example expects the `ca.pem` file to be in the same directory as the code.

```
node index.js --host <host> --port <port> --password <password>
```
