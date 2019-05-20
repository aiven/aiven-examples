CREATE TABLE IF NOT EXISTS sensor_temperature
(
    id              SERIAL  PRIMARY KEY,
    device          VARCHAR,
    label           VARCHAR,
    temperature     FLOAT
);