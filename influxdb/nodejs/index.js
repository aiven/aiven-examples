const yargs = require('yargs');
const example = require('./example');

const argv = yargs
    .option('username', {
        description: 'InfluxDB username',
        type: 'string',
        default: 'avnadmin'
    }).option('password', {
        description: 'InfluxDB password',
        type: 'string',
        required: true
    }).option('host', {
        description: 'InfluxDB host',
        type: 'string',
        required: true
    }).option('port', {
        description: 'InfluxDB port',
        required: true
    }).number('port')
    .argv;

example.influxExample(argv.username, argv.password, argv.host, argv.port);


