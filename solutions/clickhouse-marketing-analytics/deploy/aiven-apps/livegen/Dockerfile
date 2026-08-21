# livegen behind its remote-control API (campaign-datagen serve) — the load
# source for the Post 2 rate sweep, deployed next to the pipeline on Aiven
# Apps so the sweep's load never crosses the WAN (the ladder's environment
# lesson applies to drivers too).
#
# Build context: the solution root (see ../livegen/compose.yaml), so the
# image can COPY shared/datagen.
FROM python:3.12-slim

WORKDIR /app
COPY shared/datagen /app/datagen
# google-cloud-storage is only needed by `upload`; keep it out of this image.
RUN sed -i '/google-cloud-storage/d' /app/datagen/pyproject.toml \
    && pip install --no-cache-dir /app/datagen

WORKDIR /app/datagen
# One process; the serve wrapper supervises the livegen child itself.
# All knobs come from the environment (composer view) — see compose.yaml.
CMD campaign-datagen -c config.yaml serve \
      --valkey-url "$VALKEY_URI" \
      --rate "${LIVEGEN_RATE:-5000}" \
      --stream "${LIVEGEN_STREAM:-ingest:events}" \
      --pipeline "${LIVEGEN_PIPELINE:-1000}" \
      --days "${LIVEGEN_DAYS:-1}" \
      --max-stream-len "${LIVEGEN_MAX_STREAM_LEN:-1000000}" \
      --port "${LIVEGEN_PORT:-8095}" \
      ${LIVEGEN_ANCHOR:+--anchor "$LIVEGEN_ANCHOR"}
