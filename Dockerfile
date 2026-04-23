# n8n Dockerfile for Render deployment
FROM node:20-slim
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd postgresql postgresql-contrib && rm -rf /var/lib/apt/lists/*

RUN npm install -g n8n --legacy-peer-deps && npm cache clean --force

# Qdrant
ARG QDRANT_VERSION=v1.9.2
RUN curl -L "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VERSION}/qdrant-x86_64-unknown-linux-gnu.tar.gz" -o qdrant.tar.gz && \
    tar -xzf qdrant.tar.gz && mv qdrant /usr/local/bin/qdrant && rm qdrant.tar.gz && \
    mkdir -p /qdrant/storage /qdrant/config

COPY qdrant_config.yaml /qdrant/config/config.yaml


# User and directories
RUN useradd -m -s /bin/bash n8nuser
RUN mkdir -p /home/n8nuser/.n8n /data
RUN chown -R n8nuser:n8nuser /home/n8nuser /data /qdrant

ENV N8N_PORT="5678"
ENV NODE_ENV="production"

WORKDIR /home/n8nuser

COPY start.sh /start.sh
RUN chmod +x /start.sh

USER n8nuser
ENTRYPOINT ["/start.sh"]