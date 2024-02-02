CREATE DATABASE middleearth;

\c middleearth;

CREATE TABLE IF NOT EXISTS population (
    id SERIAL PRIMARY KEY,
    region INT NOT NULL,
    total INT NOT NULL
);

CREATE TABLE IF NOT EXISTS weather (
    id SERIAL PRIMARY KEY,
    region INT NOT NULL,
    temperature FLOAT NOT NULL
);

-- FULL - Emitted events for update and delete operations contain the previous values of all columns in the table. 
-- This is needed if you need to support delete operations.
ALTER TABLE population REPLICA IDENTITY FULL;
ALTER TABLE weather REPLICA IDENTITY FULL;