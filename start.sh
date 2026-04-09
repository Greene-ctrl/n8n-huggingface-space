#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Script Start ---"
echo "Running as user: $(whoami) (UID: $(id -u), GID: $(id -g))"

# --- Persistent Data Setup ---
N8N_DATA_DIR="/data/.n8n"
POSTGRES_DATA_DIR="/data/postgres"
QDRANT_DATA_DIR="/data/qdrant_storage"
OLLAMA_MODELS_DIR="/data/.ollama"

echo "Ensuring application data directories exist..."

# Create directories if they don't exist (may need root permissions)
if [ ! -d "/data" ]; then
    echo "Creating /data directory..."
    mkdir -p /data
fi

# Try to create subdirectories, if we fail (permission denied), assume we're not root
# and the directories should already exist with correct permissions from HF
if ! mkdir -p "$N8N_DATA_DIR" "$POSTGRES_DATA_DIR" "$QDRANT_DATA_DIR" "$OLLAMA_MODELS_DIR" 2>/dev/null; then
    echo "Note: Could not create directories (may already exist or permission denied). Continuing..."
fi

# Change ownership to n8nuser if we have permissions
if [ "$(id -u)" -eq 0 ]; then
    echo "Running as root. Changing ownership of /data to n8nuser..."
    chown -R n8nuser:n8nuser /data
    chmod -R u+rwx /data
    echo "Ownership changed successfully."
else
    echo "Not running as root. Checking current permissions..."
fi

echo "Permissions of data directories in /data:"
ls -ld "$N8N_DATA_DIR" "$POSTGRES_DATA_DIR" "$QDRANT_DATA_DIR" "$OLLAMA_MODELS_DIR" 2>/dev/null || echo "Some directories may not exist yet."

ln -sfn "$N8N_DATA_DIR" /home/n8nuser/.n8n
export OLLAMA_MODELS="$OLLAMA_MODELS_DIR"

# --- PostgreSQL Setup & Start (as n8nuser) ---
echo "--- PostgreSQL Setup (running as $(whoami)) ---"
echo "PGDATA is set to: $POSTGRES_DATA_DIR"
POSTGRES_PORT="${DB_POSTGRESDB_PORT:-5432}" # Define port for consistency

# Ensure n8nuser has rwx permissions on its own PGDATA.
chmod u+rwx "$POSTGRES_DATA_DIR"

if [ ! -d "$POSTGRES_DATA_DIR/base" ]; then
    echo "Initializing PostgreSQL database in $POSTGRES_DATA_DIR as user n8nuser..."
    su - n8nuser -c "/usr/lib/postgresql/14/bin/initdb -D '$POSTGRES_DATA_DIR' --username=n8nuser --no-locale --encoding=UTF8"
    if [ $? -ne 0 ]; then echo "ERROR: PostgreSQL initdb failed."; ls -ld "$POSTGRES_DATA_DIR"; exit 1; fi
    
    echo "PostgreSQL Initialized. Ownership/permissions of $POSTGRES_DATA_DIR after initdb:"
    ls -ld "$POSTGRES_DATA_DIR"

    echo "Temporarily starting PostgreSQL to create database role and database..."
    # For pg_ctl, it's good practice to point to the PGDATA explicitly.
    # pg_ctl will find postgresql.conf within PGDATA.
    su - n8nuser -c "/usr/lib/postgresql/14/bin/pg_ctl -D '$POSTGRES_DATA_DIR' -o \"-p $POSTGRES_PORT -c listen_addresses='localhost'\" -w start"
    
    PG_ROLE_NAME="${DB_POSTGRESDB_USER:-n8n}"
    PG_PASSWORD="${DB_POSTGRESDB_PASSWORD}"
    PG_DB_NAME="${DB_POSTGRESDB_DATABASE:-n8n}"

    if [ -z "$PG_PASSWORD" ]; then echo "ERROR: DB_POSTGRESDB_PASSWORD is not set."; exit 1; fi

    echo "Creating PostgreSQL role '$PG_ROLE_NAME' and database '$PG_DB_NAME'..."
    su - n8nuser -c "psql -v ON_ERROR_STOP=1 --username=n8nuser --port='$POSTGRES_PORT' --host=localhost postgres <<-EOSQL
        CREATE ROLE \"$PG_ROLE_NAME\" WITH LOGIN PASSWORD '$PG_PASSWORD';
        CREATE DATABASE \"$PG_DB_NAME\" OWNER \"$PG_ROLE_NAME\";
EOSQL
"
    echo "PostgreSQL role and database created."
    su - n8nuser -c "/usr/lib/postgresql/14/bin/pg_ctl -D '$POSTGRES_DATA_DIR' -m fast -w stop"
    echo "Temporary PostgreSQL server stopped."
else
    echo "PostgreSQL database found in $POSTGRES_DATA_DIR."
fi

echo "Starting PostgreSQL server for application use (as n8nuser)..."
# Switch to n8nuser for running services
su - n8nuser -c "/usr/lib/postgresql/14/bin/postgres -D '$POSTGRES_DATA_DIR' -p '$POSTGRES_PORT'" &
PG_PID=$!
echo "Waiting for PostgreSQL to start (PID: $PG_PID)..."
max_wait=30
count=0
until pg_isready -h localhost -p "$POSTGRES_PORT" -U n8nuser -q || [ $count -eq $max_wait ]; do
  echo -n "."
  sleep 1
  count=$((count+1))
done
if [ $count -eq $max_wait ]; then
    echo "ERROR: PostgreSQL timed out waiting to start."
    PG_LOG_DIR_GUESS="$POSTGRES_DATA_DIR/log"
    if [ -d "$PG_LOG_DIR_GUESS" ]; then
      echo "PostgreSQL logs from $PG_LOG_DIR_GUESS:"
      # List log files before cat'ing, and cat only the latest ones if possible or just one
      ls -lt "$PG_LOG_DIR_GUESS"
      cat "$PG_LOG_DIR_GUESS"/postgresql-*.log 2>/dev/null || echo "No standard log files found or readable."
    else
      echo "$PG_LOG_DIR_GUESS not found."
    fi
    exit 1
fi
echo "PostgreSQL started successfully on port $POSTGRES_PORT."


# --- Qdrant Setup & Start (as n8nuser) ---
# (This section remains the same)
echo "--- Qdrant Setup (running as $(whoami)) ---"
QDRANT_CONFIG_DIR="/qdrant/config"
QDRANT_STORAGE_PATH_IN_CONFIG="/qdrant/storage"
ln -sfn "$QDRANT_DATA_DIR" "$QDRANT_STORAGE_PATH_IN_CONFIG"

echo "Starting Qdrant (as n8nuser)..."
su - n8nuser -c "/usr/local/bin/qdrant --config-path '$QDRANT_CONFIG_DIR/config.yaml'" &
QDRANT_PID=$!
echo "Waiting for Qdrant to start (PID: $QDRANT_PID)..."
until curl -sf http://localhost:6333/readyz > /dev/null; do
    echo -n "."
    sleep 1
    if ! ps -p $QDRANT_PID > /dev/null; then echo "Qdrant process died."; exit 1; fi
done
echo "Qdrant started."

# --- Ollama Start (as n8nuser) ---
# (This section remains the same)
echo "--- Ollama Setup (running as $(whoami)) ---"
echo "Ollama models will be stored in: $OLLAMA_MODELS_DIR"

echo "Starting Ollama server (as n8nuser)..."
su - n8nuser -c "ollama serve" &
OLLAMA_PID=$!
echo "Waiting for Ollama to start (PID: $OLLAMA_PID)..."
until curl -sf http://localhost:11434/api/tags > /dev/null 2>&1 ; do
    echo -n "."
    sleep 1
    if ! ps -p $OLLAMA_PID > /dev/null; then echo "Ollama process died."; exit 1; fi
done
echo "Ollama started."

DEFAULT_MODEL="${DEFAULT_OLLAMA_MODEL:-llama3.1:8b}"
echo "Checking for default Ollama model: $DEFAULT_MODEL"
if ! ollama show "$DEFAULT_MODEL" > /dev/null 2>&1; then
    echo "Pulling $DEFAULT_MODEL... This may take a while."
    ollama pull "$DEFAULT_MODEL"
    if [ $? -ne 0 ]; then echo "Warning: Failed to pull $DEFAULT_MODEL"; else echo "$DEFAULT_MODEL pulled."; fi
else
    echo "$DEFAULT_MODEL already present."
fi

# --- n8n Start (as n8nuser) ---
echo "--- n8n Setup (running as $(whoami)) ---"

if [ -z "$N8N_ENCRYPTION_KEY" ]; then 
    echo "ERROR: N8N_ENCRYPTION_KEY is not set. Please set it as a Space secret."
    exit 1
fi
if [ -z "$DB_POSTGRESDB_PASSWORD" ]; then 
    echo "ERROR: DB_POSTGRESDB_PASSWORD is not set. Please set it as a Space secret."
    exit 1
fi

export N8N_USER_FOLDER="/home/n8nuser/.n8n"
export GENAI_MODELS_N8N_DEFAULT_MODEL="$DEFAULT_MODEL" 
export DB_POSTGRESDB_PORT="$POSTGRES_PORT" 

# URLs are already set in Dockerfile ENV, but we can override if needed
echo "N8N URLs configured:"
echo "  N8N_EDITOR_BASE_URL: $N8N_EDITOR_BASE_URL"
echo "  WEBHOOK_URL: $WEBHOOK_URL"
echo "  N8N_HOST: $N8N_HOST"
echo "  N8N_PORT: $N8N_PORT"
echo "  N8N_PROTOCOL: $N8N_PROTOCOL"

# OAuth callback configuration for ClickUp compatibility
# n8n's OAuth callback URL is constructed from WEBHOOK_URL + /rest/oauth2-credential/callback
# ClickUp trims the path, so we need to ensure the base URL is correctly configured
# In ClickUp's app settings, register: https://leon4gr45-n8n.hf.space/
# n8n will automatically handle the full callback path internally

# Optional: Increase n8n log level for more startup details
# export N8N_LOG_LEVEL="debug" 

echo "Before su: environment variables"
env | grep N8N

echo "Starting n8n (as n8nuser) with highly permissive (INSECURE) embedding rules for diagnosis..."
su n8nuser -c "echo 'Inside su:' && env | grep N8N && n8n start"