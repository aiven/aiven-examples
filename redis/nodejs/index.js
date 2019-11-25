const yargs = require('yargs');
const example = require('./example');

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

example.redisExample(argv.host, argv.port, argv.password);
