#!/bin/bash
# =============================================================================
# PostgreSQL Multi-Database Initialization Script
# =============================================================================
# Creates multiple databases within a single PostgreSQL instance:
#   - postiz: Main application database
#   - temporal: Workflow engine database
#   - temporal_visibility: Temporal visibility database
# =============================================================================

set -e

# Use environment variables or defaults
POSTIZ_DB="${POSTIZ_DB:-postiz}"
TEMPORAL_DB="${TEMPORAL_DB:-temporal}"

echo "Creating database: $POSTIZ_DB"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "$POSTIZ_DB";
EOSQL

echo "Creating database: $TEMPORAL_DB"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "$TEMPORAL_DB";
EOSQL

echo "Creating database: ${TEMPORAL_DB}_visibility"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "${TEMPORAL_DB}_visibility";
EOSQL

echo "All databases created successfully"
