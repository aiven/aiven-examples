# Dockerfile for the live-orders producer, built for deployment to Aiven Apps.
#
# All configuration (KAFKA_SERVICE_URI, KAFKA_USERNAME, KAFKA_PASSWORD, and the
# optional KAFKA_TOPIC / ORDERS_PER_MINUTE / PORT) is injected at runtime via
# Aiven Apps environment variables / secrets — nothing is baked into the image.

# ---- build stage ----
FROM golang:1.24 AS build
WORKDIR /src

# Cache module downloads first.
COPY go.mod go.sum* ./
RUN go mod download

COPY . .
# Static binary so it runs on a minimal base image.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/live-orders .

# ---- runtime stage ----
# distroless: no shell, small surface; includes CA certs for the SASL_SSL/TLS
# connection to Aiven Kafka (Let's Encrypt chain trusted via system roots).
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/live-orders /app/live-orders

# The producer also serves a small health endpoint so Aiven Apps has a port to
# probe (PORT, default 8080): /healthz (liveness) and /readyz (ready once the
# Kafka producer connects).
EXPOSE 8080
ENTRYPOINT ["/app/live-orders"]
