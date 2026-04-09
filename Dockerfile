# Minimal n8n Dockerfile for Hugging Face Space
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl wget gnupg sudo procps net-tools ca-certificates postgresql postgresql-contrib zstd && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

RUN npm install -g n8n

ARG QDRANT_VERSION=v1.9.2
RUN wget "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VERSION}/qdrant-x86_64-unknown-linux-gnu.tar.gz" -O qdrant.tar.gz && tar -xzf qdrant.tar.gz && mv qdrant /usr/local/bin/qdrant && rm qdrant.tar.gz && mkdir -p /qdrant/storage && mkdir -p /qdrant/config
COPY qdrant_config.yaml /qdrant/config/config.yaml

RUN curl -fsSL https://ollama.com/install.sh | sh

RUN useradd -m -s /bin/bash n8nuser
RUN mkdir -p /home/n8nuser/.n8n /data/shared /home/n8nuser/.ollama /var/run/postgresql
RUN chown -R n8nuser:n8nuser /home/n8nuser /data/shared /qdrant /var/run/postgresql

# Environment variables - n8n will use these for OAuth callback validation
ENV N8N_PORT="5678"
ENV N8N_URL="https://n8n-clickup-oauth-proxy.vercel.app/"
ENV N8N_PROTOCOL="https"
ENV N8N_HOST="n8n-clickup-oauth-proxy.vercel.app"
ENV N8N_EDITOR_BASE_URL="https://n8n-clickup-oauth-proxy.vercel.app/"
ENV WEBHOOK_URL="https://n8n-clickup-oauth-proxy.vercel.app/"
ENV N8N_TRUST_PROXY="true"
ENV NODE_ENV="production"
ENV DB_TYPE="postgresdb"
ENV DB_POSTGRESDB_HOST="localhost"
ENV DB_POSTGRESDB_PORT="5432"
ENV DB_POSTGRESDB_DATABASE="n8n"
ENV DB_POSTGRESDB_USER="n8n"
ENV OLLAMA_HOST="0.0.0.0:11434"

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 5678
EXPOSE 11434
EXPOSE 6333
EXPOSE 5432

USER root
ENTRYPOINT ["/start.sh"]
