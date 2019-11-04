const Kafka = require('node-rdkafka');

if (!Kafka.features.includes('ssl')) {
    console.log('This example requires node-rdkafka is compiled with ssl support. See README for more information.');
    process.exit(1)
}

TOPIC = 'nodejs_example_topic';

function kafkaExample(host, keyPath, certPath, caPath) {
    const producer = new Kafka.Producer({
        'metadata.broker.list': host,
        'security.protocol': 'ssl',
        'ssl.key.location': keyPath,
        'ssl.certificate.location': certPath,
        'ssl.ca.location': caPath,
        'dr_cb': true
    });

    producer.connect();
    producer.on('ready', function () {
        try {
            producer.produce(
                TOPIC,  // topic to send the message to
                null,  // partition, null for librdkafka default partitioner
                new Buffer.from('Hello world!'),  // value
                null,  // optional key
                Date.now()  // optional timestamp
            );
            producer.flush(2000);
            console.log('Message sent successfully');
        } catch (err) {
            console.log('Failed to send message', err);
        }
        producer.disconnect();
    });

    const stream = new Kafka.createReadStream({
        'metadata.broker.list': host,
        'group.id': 'demo-consumer-group',
        'security.protocol': 'ssl',
        'ssl.key.location': keyPath,
        'ssl.certificate.location': certPath,
        'ssl.ca.location': caPath,
        'enable.auto.commit': false,
    }, {'auto.offset.reset': 'earliest'}, {'topics': [TOPIC]});

    stream.on('data', function (message) {
        console.log('Got message: ' + message.value.toString());
        process.exit(0);
    });
}

module.exports = {
    kafkaExample: kafkaExample
};

