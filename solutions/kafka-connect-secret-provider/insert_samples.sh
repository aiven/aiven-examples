#!/bin/bash

ROWS_TO_INSERT=10
PG_URI=$(terraform output -raw pg_uri)
TABLE_NAME=test

# Function to generate random string
generate_random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1
}

# Create table SQL
create_table_sql="
CREATE TABLE IF NOT EXISTS $TABLE_NAME (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    value INT NOT NULL
);
"

# Insert data SQL
insert_data_sql="INSERT INTO $TABLE_NAME (name, value) VALUES "

# Generate insert statements
for ((i=1; i<=ROWS_TO_INSERT; i++)); do
    name=$(generate_random_string)
    value=$((RANDOM % 100))
    if [ $i -ne $ROWS_TO_INSERT ]; then
        insert_data_sql+="('$name', $value),"
    else
        insert_data_sql+="('$name', $value);"
    fi
done

# Combine create table and insert data SQL
sql="$create_table_sql $insert_data_sql"


# Execute SQL
psql $PG_URI -c "$sql"
