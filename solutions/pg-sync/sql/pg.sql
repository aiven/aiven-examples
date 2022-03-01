CREATE TABLE heartbeat (
    status SMALLINT
);

CREATE SEQUENCE all_datatypes_seq;
CREATE TYPE enum_column_type AS ENUM ('1', '2', '3');

CREATE TABLE all_datatypes (
  id INT check (id > 0) NOT NULL DEFAULT NEXTVAL ('all_datatypes_seq'), -- Unique ID for the record

  int_column INT,
  bigint_column BIGINT,
  float_column DOUBLE PRECISION,
  decimal_column DECIMAL( 10, 2 ),

  date_column DATE,
  datetime_column TIMESTAMP(0),
  time_column TIME(0),
  year_column NUMERIC(4),

  char_column CHAR( 10 ),
  varchar_column VARCHAR( 20 ),
  blob_column BYTEA,
  text_column TEXT,
  enum_column enum_column_type,
  set_column enum_column_type[],

  bool_column BOOL,

  json_column json,

  PRIMARY KEY     (id)
);

ALTER TABLE public.all_datatypes REPLICA IDENTITY FULL;

INSERT INTO public.all_datatypes ( int_column, bigint_column, float_column, decimal_column, date_column, datetime_column, time_column, year_column, char_column, varchar_column, blob_column, text_column, enum_column, set_column, bool_column, json_column )
VALUES ( 1111, 11111111, 111111.11, 11111111.11, '1000-01-01', '1971-01-01 01:01:01', '11:11:11', 1901, 'A', 'AAA', 'blob_AAA', 'text_AAA', '1', '{1}', true, '{"foo":"bar"}');

INSERT INTO public.all_datatypes ( int_column, bigint_column, float_column, decimal_column, date_column, datetime_column, time_column, year_column, char_column, varchar_column, blob_column, text_column, enum_column, set_column, bool_column, json_column )
VALUES ( 2222, null, 222222.22, 22222222.22, '2000-02-02', '2972-02-02 02:02:02', '02:22:22', 2902, 'B', 'BBB', 'blob_BBB', 'text_BBB', '2', '{2}', false, '{"baz":"yak"}');

INSERT INTO public.all_datatypes ( int_column, bigint_column, float_column, decimal_column, date_column, datetime_column, time_column, year_column, char_column, varchar_column, blob_column, text_column, enum_column, set_column, bool_column, json_column )
VALUES ( 3333, 33333333, 333333.33, 33333333.33, '3000-03-03', '3973-03-03 03:03:03', '03:33:33', 3903, 'C', 'CCC', 'blob_CCC', 'text_CCC', '3', '{1,3}', true, '{"jack":"jill"}');

