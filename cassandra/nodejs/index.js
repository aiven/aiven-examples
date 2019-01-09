const fs = require('fs');
const cassandra = require('cassandra-driver');

const authProvider = new cassandra.auth.PlainTextAuthProvider('avnadmin', '<your password>');
const client = new cassandra.Client({
    contactPoints: ['cassandra-3b8d4ed6-myfirstcloudhub.aivencloud.com:12691'],
    localDataCenter: 'aiven',
    sslOptions: {
        cert: fs.readFileSync('ca.pem')
    },
    authProvider
});

client.execute("CREATE KEYSPACE example_keyspace WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'aiven': 3}")
    .then(() => client.execute("USE example_keyspace"))
    .then(() => client.execute("CREATE TABLE example_table (id int PRIMARY KEY, message text)"))
    .then(() => client.execute("INSERT INTO example_table (id, message) VALUES (?, ?)", [123, "Hello world!"], { prepare: true }))
    .then(() => client.execute("SELECT id, message FROM example_table"))
    .then(results => results.rows.forEach(row => console.log('Row: id = ' + row.id + ', message = ' + row.message)))
    .then(() => client.shutdown())
    .catch(error => console.error(error));
