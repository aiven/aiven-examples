const yargs = require('yargs');
const example = require('./example');

const argv = yargs
    .option('host', {
        description: 'Postgres host',
        type: 'string',
        required: true
    }).option('port', {
        description: 'Postgres port',
        type: 'string',
        required: true
    }).option('password', {
        description: 'Postgres password',
        type: 'string',
        required: true
    }).option('user', {
        description: 'Postgres user',
        type: 'string',
        default: 'avnadmin'
    }).number("port")
    .argv;

example.postgresExample(argv.host, argv.password, argv.port, argv.user);

