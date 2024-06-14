CREATE TABLE IF NOT EXISTS weather_stations (roadstationid smallint primary key, name varchar(128), municipality varchar(64), province varchar(64), latitude float, longitude float);
CREATE TABLE IF NOT EXISTS weather_sensors (sensorid smallint primary key, name varchar(128), unit varchar(8), accuracy smallint);

