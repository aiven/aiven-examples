CREATE TABLE public.employees (
  id INT NOT NULL,
  first_name VARCHAR(45) NOT NULL,
  last_name VARCHAR(45) NOT NULL,
  title VARCHAR(45) NOT NULL,
  PRIMARY KEY (id));

CREATE SEQUENCE all_datatypes_seq;
CREATE TYPE enum_column_type AS ENUM ('1', '2', '3');

CREATE TABLE all_datatypes (
  id INT check (id > 0) NOT NULL DEFAULT NEXTVAL ('all_datatypes_seq'), -- Unique ID for the record

  int_column INT,
  tinyint_column SMALLINT,
  smallint_column SMALLINT,
  mediumint_column INT,
  bigint_column BIGINT,
  float_column DOUBLE PRECISION,
  double_column DOUBLE PRECISION,
  decimal_column DECIMAL( 10, 2 ),

  date_column DATE,
  datetime_column TIMESTAMP(0),
  timestamp_column TIMESTAMP(0),
  time_column TIME(0),
  year_column NUMERIC(4),

  char_column CHAR( 10 ),
  varchar_column VARCHAR( 20 ),
  blob_column BYTEA,
  text_column TEXT,
  tinyblob_column BYTEA,
  tinytext_column TEXT,
  mediumblob_column BYTEA,
  mediumtext_column TEXT,
  longblob_column BYTEA,
  longtext_column TEXT,
  enum_column enum_column_type,
  set_column enum_column_type[],

  bool_column BOOL,
  binary_column BYTEA,
  varbinary_column BYTEA,

  PRIMARY KEY     (id)
);
