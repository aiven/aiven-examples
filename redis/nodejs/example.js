const Redis = require('ioredis');

function redisExample(host, port, password) {
    const redis = new Redis({
        host: host,
        port: port,
        password: password,
        tls: true,
    });

    redis.set('nodejsExample', 'node.js');
    redis.get('nodejsExample', function (err, result) {
        if (err) {
            console.log(err);
            process.exit(1);
        }

        console.log("The value for 'nodejsExample' is: " + result);
        process.exit(0);
    });
}

module.exports = {
    redisExample: redisExample
}