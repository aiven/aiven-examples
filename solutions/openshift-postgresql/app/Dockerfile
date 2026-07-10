FROM python:3.14-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# OpenShift runs containers as an arbitrary non-root UID by default.
# Dropping to a non-root user here satisfies the restricted SCC without
# needing a custom SecurityContextConstraints.
RUN useradd --uid 1001 --no-create-home appuser
USER 1001

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
