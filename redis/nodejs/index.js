const Redis = require('ioredis');

const yargs = require('yargs');

const argv = yargs
    .option('host', {
        description: 'Redis host',
        type: 'string',
        required: true
    }).option('port', {
        description: 'Redis port',
        type: 'string',
        required: true
    }).option('password', {
        description: 'Redis password',
        type: 'string',
        required: true
    }).number("port")
    .argv;


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

redisExample(argv.host, argv.port, argv.password);
