# Dockerfile for the query-agent web app, built for deployment to Aiven Apps.
#
# Config (AWS_REGION, BEDROCK_MODEL_ID, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# TRINO_MCP_URL, TRINO_MCP_JWT) is injected at runtime via Aiven Apps env vars /
# secrets — nothing is baked into the image.

FROM python:3.12-slim

WORKDIR /app

# Install deps first for layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY helpers.py .
COPY static/ ./static/

# Web UI port (override with PORT).
ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT}"]
