FROM python:3.11-alpine

RUN apk add --no-cache wget && rm -rf /var/cache/apk/*

WORKDIR /app

COPY frontend/server.py .
COPY frontend/index.html .

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

CMD ["python3", "server.py"]

