# query-app: a single deployable image for Aiven Apps.
#
# Bundles Trino + the Trino MCP server (mcp-trino) into ONE container, with the
# Trino config baked in. Aiven Apps deploys a single buildable service per app
# (no pre-built image pull, no multi-service compose, no bind-mount volumes), so
# the original two-container compose is collapsed into this image.
#
# The only externally reachable surface is the MCP endpoint on :9097. Trino
# listens on localhost:8080 *inside* the container and is never exposed.
#
# Secrets are NOT baked in: trino/etc/catalog/iceberg.properties uses ${ENV:...}
# expanded by Trino at startup, and the MCP auth secret comes from env at runtime.

# --- Stage 1: lift the statically-linked mcp-trino binary -------------------
# It's a static Go binary, so it drops cleanly into the glibc-based Trino image,
# and `docker build` selects the arch matching the build host automatically.
# Pinned to a released tag for reproducibility (bump deliberately).
ARG MCP_TRINO_IMAGE=ghcr.io/tuannvm/mcp-trino:4.3.1
FROM ${MCP_TRINO_IMAGE} AS mcp

# --- Stage 2: Trino + baked config + the MCP binary -------------------------
# Pinned to a specific Trino release for reproducibility (bump deliberately).
FROM trinodb/trino:482

# COPY/chmod need root; the base image runs as the unprivileged "trino" user.
USER root

# Trino configuration (catalogs, read-only access control, JVM) baked in.
COPY trino/etc /etc/trino

# The co-located MCP server.
COPY --from=mcp /app/trino-mcp /usr/local/bin/trino-mcp

# Starts Trino, waits until it's ready, then execs the MCP server.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/trino-mcp /usr/local/bin/entrypoint.sh

# Back to the unprivileged user the base image ships with.
USER trino:trino

# Wiring for mcp-trino -> the co-located Trino. Override at deploy time if needed.
# Secrets (JWT_SECRET) and toggles (OAUTH_*) are supplied via env, not baked here.
ENV MCP_TRANSPORT=http \
    MCP_PORT=9097 \
    TRINO_HOST=localhost \
    TRINO_PORT=8080 \
    TRINO_SCHEME=http \
    TRINO_USER=trino \
    TRINO_CATALOG=iceberg

# Only the MCP endpoint is exposed; Trino's 8080 stays container-internal.
EXPOSE 9097

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
