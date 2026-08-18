# One entry point per phase of the Post 2 demo (see 02-dashboard-mv/README.md).
# Local defaults; point CH_URL/CH_USER/CH_PASSWORD at Aiven to run there.
SHELL := /bin/bash
CH_CONTAINER ?= clickhouse-marketing-analytics-clickhouse-1
CH_DATABASE  ?= campaign_analytics
CH_PASSWORD  ?= local
CH_ENV       := CH_DATABASE=$(CH_DATABASE) CH_PASSWORD=$(CH_PASSWORD) $(if $(CH_URL),CH_URL=$(CH_URL)) $(if $(CH_USER),CH_USER=$(CH_USER))
DATAGEN      := cd shared/datagen && .venv/bin/campaign-datagen
CLIENT       := docker exec -i $(CH_CONTAINER) clickhouse-client --password $(CH_PASSWORD) --database $(CH_DATABASE) --multiquery
SMOKE_OUT    := shared/datagen/out-smoke/campaign_events
BENCH_LABEL  ?= idle

.PHONY: up down datagen datagen-smoke optimize ingest-smoke project verify bench live report

up:
	docker compose up -d clickhouse valkey

down:
	docker compose down

datagen-smoke:
	$(DATAGEN) -c config-smoke.yaml generate

datagen:
	$(DATAGEN) generate   # full ~500M config.yaml run

# Rollups + MVs. Run BEFORE ingest so the MVs fire on every inserted block;
# for data loaded earlier, run the backfill INSERTs at the bottom of the DDL files.
optimize:
	$(CLIENT) < 02-dashboard-mv/ddl/01_daily_campaign_rollup.sql
	$(CLIENT) < 02-dashboard-mv/ddl/04_query_rollups.sql

ingest-smoke:
	@for f in $(SMOKE_OUT)/month=*/part-*.parquet; do \
	  echo "insert $$f"; \
	  curl -sf "http://localhost:8123/?database=$(CH_DATABASE)&query=INSERT%20INTO%20campaign_events%20SETTINGS%20async_insert%3D0%20FORMAT%20Parquet" \
	    -H 'X-ClickHouse-User: default' -H 'X-ClickHouse-Key: $(CH_PASSWORD)' --data-binary @$$f || exit 1; \
	done
	docker exec $(CH_CONTAINER) clickhouse-client --password $(CH_PASSWORD) --database $(CH_DATABASE) \
	  -q "SELECT count() AS raw FROM campaign_events; SELECT sum(events) AS rollup_events FROM daily_campaign_rollup"

project:
	$(CLIENT) < 02-dashboard-mv/ddl/05_user_journey_projection.sql

verify:
	cd 02-dashboard-mv/bench && $(CH_ENV) python3 verify_equality.py

bench:
	cd 02-dashboard-mv/bench && $(CH_ENV) python3 run_suite.py --track both --label $(BENCH_LABEL)

live:
	02-dashboard-mv/live/run_day90.sh

report:
	cd 02-dashboard-mv/report && $(CH_ENV) python3 server.py 8088
