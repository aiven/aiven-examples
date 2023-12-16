# clickhouse-dbt

This demostrates how to integrate dbt with ClickHouse for Aiven by following the steps in https://clickhouse.com/docs/en/integrations/dbt


## Requirements

- `avn`
- `jq`


## Steps

- Update the `PROJECT` and `SERVICE` in `ch-dbt.env`

Run the following to download clickhouse CLI and setup required service and databases.
```
./ch-dbt.sh setup
```

Run the following to load sample data, setup dbt and the ClickHouse plugin, then creates a Simple View Materialization.  dbt will represent the model as a view in ClickHouse as requested and finally query this view. 
```
./ch-dbt.sh demo
```

Run the following to delete all the resources created in this demo.
```
./ch-dbt.sh teardown
```

## Successful Demo Run

```
$ ./ch-dbt.sh demo
...
CREATE TABLE IF NOT EXISTS imdb.actors
(
    id         UInt32,
    first_name String,
    last_name  String,
    gender     FixedString(1)
) ENGINE = MergeTree ORDER BY (id, first_name, last_name, gender);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.052
Processed rows: 1
CREATE TABLE IF NOT EXISTS imdb.directors
(
    id         UInt32,
    first_name String,
    last_name  String
) ENGINE = MergeTree ORDER BY (id, first_name, last_name);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.052
Processed rows: 1
CREATE TABLE IF NOT EXISTS imdb.genres
(
    movie_id UInt32,
    genre    String
) ENGINE = MergeTree ORDER BY (movie_id, genre);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.049
Processed rows: 1
CREATE TABLE IF NOT EXISTS imdb.movie_directors
(
    director_id UInt32,
    movie_id    UInt64
) ENGINE = MergeTree ORDER BY (director_id, movie_id);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.035
Processed rows: 1
CREATE TABLE IF NOT EXISTS imdb.movies
(
    id   UInt32,
    name String,
    year UInt32,
    rank Float32 DEFAULT 0
) ENGINE = MergeTree ORDER BY (id, name, year);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.042
Processed rows: 1
CREATE TABLE IF NOT EXISTS imdb.roles
(
    actor_id   UInt32,
    movie_id   UInt32,
    role       String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree ORDER BY (actor_id, movie_id);
s_36113	clickhouse-dbt-1.felixwu-demo.aiven.local	OK	0	0
0.082
Processed rows: 1
INSERT INTO imdb.actors
SELECT *
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_actors.tsv.gz',
'TSVWithNames');
2.023
Processed rows: 0
INSERT INTO imdb.directors
SELECT *
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_directors.tsv.gz',
'TSVWithNames');
1.449
Processed rows: 0
INSERT INTO imdb.genres
SELECT *
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_movies_genres.tsv.gz',
'TSVWithNames');
1.629
Processed rows: 0
INSERT INTO imdb.movie_directors
SELECT *
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_movies_directors.tsv.gz',
        'TSVWithNames');
1.582
Processed rows: 0
INSERT INTO imdb.movies
SELECT *
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_movies.tsv.gz',
'TSVWithNames');
1.839
Processed rows: 0
INSERT INTO imdb.roles(actor_id, movie_id, role)
SELECT actor_id, movie_id, role
FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_roles.tsv.gz',
'TSVWithNames');
2.894
Processed rows: 0
SELECT id,
       any(actor_name)          as name,
       uniqExact(movie_id)    as num_movies,
       avg(rank)                as avg_rank,
       uniqExact(genre)         as unique_genres,
       uniqExact(director_name) as uniq_directors,
       max(created_at)          as updated_at
FROM (
         SELECT imdb.actors.id  as id,
                concat(imdb.actors.first_name, ' ', imdb.actors.last_name)  as actor_name,
                imdb.movies.id as movie_id,
                imdb.movies.rank as rank,
                genre,
                concat(imdb.directors.first_name, ' ', imdb.directors.last_name) as director_name,
                created_at
         FROM imdb.actors
                  JOIN imdb.roles ON imdb.roles.actor_id = imdb.actors.id
                  LEFT OUTER JOIN imdb.movies ON imdb.movies.id = imdb.roles.movie_id
                  LEFT OUTER JOIN imdb.genres ON imdb.genres.movie_id = imdb.movies.id
                  LEFT OUTER JOIN imdb.movie_directors ON imdb.movie_directors.movie_id = imdb.movies.id
                  LEFT OUTER JOIN imdb.directors ON imdb.directors.id = imdb.movie_directors.director_id
         )
GROUP BY id
ORDER BY num_movies DESC
LIMIT 5;
45332	Mel Blanc	909	5.7884792542982515	19	148	2023-12-16 05:28:51
621468	Bess Flowers	672	5.540605094212635	20	301	2023-12-16 05:28:51
283127	Tom London	549	2.8057034230202023	18	208	2023-12-16 05:28:51
89951	Edmund Cobb	544	2.72430730046193	17	203	2023-12-16 05:28:51
41669	Adoor Bhasi	544	0	4	121	2023-12-16 05:28:51
4.244
Processed rows: 5
05:29:00  Running with dbt=1.7.4
05:29:00
Your new dbt project "imdb" was created!

For more information on how to configure the profiles.yml file,
please consult the dbt documentation here:

  https://docs.getdbt.com/docs/configure-your-profile

One more thing:

Need help? Don't hesitate to reach out to us via GitHub issues or on Slack:

  https://community.getdbt.com/

Happy modeling!

05:29:00  Setting up your profile.
Which database would you like to use?
[1] clickhouse

(Don't see the one you want? https://docs.getdbt.com/docs/available-adapters)

Enter a number: 05:29:00  No sample profile found for clickhouse.
05:29:02  Running with dbt=1.7.4
05:29:02  dbt version: 1.7.4
05:29:02  python version: 3.11.5
05:29:02  python path: /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11
05:29:02  os info: macOS-13.6.2-arm64-arm-64bit
05:29:02  Using profiles dir at /Users/felix.wu/coderepo/aiven-examples/solutions/clickhouse-dbt/imdb
05:29:02  Using profiles.yml file at /Users/felix.wu/coderepo/aiven-examples/solutions/clickhouse-dbt/imdb/profiles.yml
05:29:02  Using dbt_project.yml file at /Users/felix.wu/coderepo/aiven-examples/solutions/clickhouse-dbt/imdb/dbt_project.yml
05:29:02  adapter type: clickhouse
05:29:02  adapter version: 1.7.1
05:29:02  Configuration:
05:29:02    profiles.yml file [OK found and valid]
05:29:02    dbt_project.yml file [OK found and valid]
05:29:02  Required dependencies:
05:29:02   - git [OK found]

05:29:02  Connection:
05:29:02    driver: None
05:29:02    host: clickhouse-dbt-felixwu-demo.a.aivencloud.com
05:29:02    port: 24948
05:29:02    user: avnadmin
05:29:02    schema: imdb_dbt
05:29:02    retries: 1
05:29:02    database_engine: None
05:29:02    cluster_mode: False
05:29:02    secure: True
05:29:02    verify: False
05:29:02    connect_timeout: 10
05:29:02    send_receive_timeout: 300
05:29:02    sync_request_timeout: 5
05:29:02    compress_block_size: 1048576
05:29:02    compression:
05:29:02    check_exchange: True
05:29:02    custom_settings: None
05:29:02    use_lw_deletes: False
05:29:02    allow_automatic_deduplication: False
05:29:02  Registered adapter: clickhouse=1.7.1
05:29:04    Connection test: [OK connection ok]

05:29:04  All checks passed!
05:29:05  Running with dbt=1.7.4
05:29:05  Registered adapter: clickhouse=1.7.1
05:29:05  Unable to do partial parsing because saved manifest not found. Starting full parse.
05:29:06  Found 1 model, 6 sources, 0 exposures, 0 metrics, 421 macros, 0 groups, 0 semantic models
05:29:06
05:29:07  Concurrency: 1 threads (target='dev')
05:29:07
05:29:07  1 of 1 START sql view model `imdb_dbt`.`actor_summary` ......................... [RUN]
05:29:07  1 of 1 OK created sql view model `imdb_dbt`.`actor_summary` .................... [OK in 0.15s]
05:29:07
05:29:07  Finished running 1 view model in 0 hours 0 minutes and 1.42 seconds (1.42s).
05:29:07
05:29:07  Completed successfully
05:29:07
05:29:07  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
SHOW DATABASES;
INFORMATION_SCHEMA
default
imdb
imdb_dbt
information_schema
system
0.001
Processed rows: 6
SELECT * FROM imdb_dbt.actor_summary ORDER BY num_movies DESC LIMIT 5;
45332	Mel Blanc	909	5.7884792542982515	19	148	2023-12-16 05:28:51
621468	Bess Flowers	672	5.540605094212635	20	301	2023-12-16 05:28:51
283127	Tom London	549	2.8057034230202023	18	208	2023-12-16 05:28:51
41669	Adoor Bhasi	544	0	4	121	2023-12-16 05:28:51
89951	Edmund Cobb	544	2.72430730046193	17	203	2023-12-16 05:28:51
4.082
Processed rows: 5
```