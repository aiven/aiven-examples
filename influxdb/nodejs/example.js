const Influx = require('influx');

function influxExample(username, password, host, port) {
    const influxDB = new Influx.InfluxDB({
        protocol: 'https',
        host: host,
        database: 'defaultdb',
        port: port,
        username: username,
        password: password,
    });

    // Write some data
    influxDB.writePoints([
        {
            measurement: 'meas',
            tags: {host: 'foo'},
            fields: {duration: 10, path: 'bar'},
        }
    ]).catch(function (err) {
        console.error('Error saving data to InfluxDB!')
    });

    // Read some data
    influxDB.query(
        'select "duration", time from meas where time > now() - 1h'
    ).then(function (result) {
        console.log(result);
    });
}

module.exports = {
    influxExample: influxExample
};
