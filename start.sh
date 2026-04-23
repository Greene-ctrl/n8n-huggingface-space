#!/bin/bash
set -e

echo "--- Script Start ---"
echo "Running as user: $(whoami) (UID: $(id -u), GID: $(id -g))"

# --- Persistent Data Setup ---
N8N_DATA_DIR="/data/.n8n"
POSTGRES_DATA_DIR="/data/postgres"
QDRANT_DATA_DIR="/data/qdrant_storage"

echo "Ensuring application data directories exist..."
mkdir -p "$N8N_DATA_DIR" "$POSTGRES_DATA_DIR" "$QDRANT_DATA_DIR"
echo "Permissions of data directories:"
ls -ld "$N8N_DATA_DIR" "$POSTGRES_DATA_DIR" "$QDRANT_DATA_DIR"

ln -sfn "$N8N_DATA_DIR" /home/n8nuser/.n8n

# --- PostgreSQL Setup & Start (if using local DB) ---
if [ -n "$USE_LOCAL_POSTGRES" ]; then
    PG_BIN_DIR=$(ls -d /usr/lib/postgresql/*/bin | head -n 1)
    if [ -z "$PG_BIN_DIR" ]; then
        echo "ERROR: PostgreSQL binaries not found."
        exit 1
    fi
    export PATH="$PG_BIN_DIR:$PATH"
    echo "--- PostgreSQL Setup (local mode) ---"
    POSTGRES_PORT="${DB_POSTGRESDB_PORT:-5432}"
    chmod u+rwx "$POSTGRES_DATA_DIR"

    if [ ! -d "$POSTGRES_DATA_DIR/base" ]; then
        echo "Initializing PostgreSQL..."
        initdb -D "$POSTGRES_DATA_DIR" --username=n8nuser --no-locale --encoding=UTF8
        echo "PostgreSQL Initialized."
    fi

    echo "Starting PostgreSQL..."
    postgres -D "$POSTGRES_DATA_DIR" -p "$POSTGRES_PORT" -c unix_socket_directories='/tmp' &
    PG_PID=$!
    
    until pg_isready -h localhost -p "$POSTGRES_PORT" -U n8nuser -q; do
        echo -n "."
        sleep 1
    done
    echo "PostgreSQL started on port $POSTGRES_PORT."

    # Create role and database
    PG_ROLE_NAME="${DB_POSTGRESDB_USER:-n8n}"
    PG_PASSWORD="${DB_POSTGRESDB_PASSWORD}"
    PG_DB_NAME="${DB_POSTGRESDB_DATABASE:-n8n}"

    if [ -z "$PG_PASSWORD" ]; then 
        echo "ERROR: DB_POSTGRESDB_PASSWORD is not set."
        exit 1
    fi

    psql -v ON_ERROR_STOP=1 --username=n8nuser --port="$POSTGRES_PORT" --host='/tmp' postgres <<-EOSQL
        CREATE ROLE "$PG_ROLE_NAME" WITH LOGIN PASSWORD '$PG_PASSWORD';
        CREATE DATABASE "$PG_DB_NAME" OWNER "$PG_ROLE_NAME";
EOSQL
    echo "PostgreSQL database created."

    export DB_TYPE="postgresdb"
    export DB_POSTGRESDB_HOST="localhost"
    export DB_POSTGRESDB_PORT="$POSTGRES_PORT"
    export DB_POSTGRESDB_DATABASE="$PG_DB_NAME"
    export DB_POSTGRESDB_USER="$PG_ROLE_NAME"
    export DB_POSTGRESDB_PASSWORD="$PG_PASSWORD"
fi

# --- Qdrant Setup & Start ---
echo "--- Qdrant Setup ---"
QDRANT_CONFIG_DIR="/qdrant/config"
QDRANT_STORAGE_PATH_IN_CONFIG="/qdrant/storage"
rm -rf "$QDRANT_STORAGE_PATH_IN_CONFIG"
ln -sfn "$QDRANT_DATA_DIR" "$QDRANT_STORAGE_PATH_IN_CONFIG"

/usr/local/bin/qdrant --config-path "$QDRANT_CONFIG_DIR/config.yaml" &
until curl -sf http://localhost:6333/readyz > /dev/null; do sleep 1; done
echo "Qdrant started."


# --- n8n Start ---
echo "--- n8n Setup ---"

if [ -z "$N8N_ENCRYPTION_KEY" ]; then
    echo "ERROR: N8N_ENCRYPTION_KEY is not set."
    exit 1
fi

if [ -z "$DB_TYPE" ]; then
    echo "ERROR: DB_TYPE is not set. Set USE_LOCAL_POSTGRES=1 for local DB."
    exit 1
fi

export N8N_USER_FOLDER="/home/n8nuser/.n8n"

echo "Using PostgreSQL: $DB_POSTGRESDB_HOST:$DB_POSTGRESDB_PORT/$DB_POSTGRESDB_DATABASE"
echo "N8N URLs: $N8N_EDITOR_BASE_URL"

exec n8n start