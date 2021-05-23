<?php

require "vendor/autoload.php";

// parse the CLI arguments
$longopts = [
    "host:",
    "port:",
    "user:",
    "password:",
];
$args = getopt("",$longopts);

// create a client
$client = new InfluxDB\Client(
    $args["host"],
    $args["port"],
    $args["user"],
    $args["password"],
    true,
    true,
);

// construct a data point
$point = new InfluxDB\Point(
		'php_example_metric', // name of the measurement
		0.64, // the measurement value
		['host' => 'server1', 'location' => 'EU-DE-22'], // optional tags
		['cpucount' => 8], // optional additional fields
);

// write to the database using the path
$result = $client->write(["url" => "api/v1/influxdb/write?db=default"], $point);
var_dump($result);
