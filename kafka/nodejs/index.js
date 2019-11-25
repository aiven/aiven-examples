const yargs = require('yargs');
const example = require('./example');

const argv = yargs
    .option('host', {
        description: 'Kafka host in the form host:port',
        type: 'string',
        required: true
    }).option('host', {
        description: 'InfluxDB host',
        type: 'string',
        required: true
    }).option('key-path', {
        description: 'Path to service.key',
        type: 'string',
        required: true
    }).option('cert-path', {
        description: 'Path to service.cert',
        type: 'string',
        required: true
    }).option('ca-path', {
        description: 'Path to ca.pem',
        type: 'string',
        required: true
    })
    .argv;


example.kafkaExample(argv.host, argv.keyPath, argv.certPath, argv.caPath);

