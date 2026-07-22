FROM python:3.13-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY publisher.py .

USER nobody
EXPOSE 8080
CMD ["python", "-u", "publisher.py"]
