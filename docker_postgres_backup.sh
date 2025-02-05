#!/bin/bash

## PostgreSQL Docker Container Backup Script
# Purpose: Automated backup solution for PostgreSQL databases in Docker containers
# Features:
# - Creates SQL dump and compressed data directory backup
# - Comprehensive integrity checks (file size, checksum validation)
# - Container cleanup after successful backup
# - Error handling with immediate failure on critical issues
# - Configurable minimum file sizes and container name
#
# Output files:
#  1. SQL dump file: sql_full_dump_YYYYMMDD_HHMMSS.sql
#  2. Compressed database files: postgresql_files_YYYYMMDD_HHMMSS.tar.gz
#  3. PostgreSQL version info: postgresql_version.txt
#
# File locations:
#  - Inside container: Created in /home/ directory
#  - Host system: Copied to backups directory in the script's current working directory
#
# Notes:
#  - --clean option in pg_dumpall: Adds DROP statements before each object
#    to enable clean reinstall by removing existing objects


set -euo pipefail

# ------------------
# Configuration
# ------------------
DB_NAME_SUBSTRING="biomaps_db"
MIN_SQL_SIZE=102400    # 100KB minimum expected SQL dump size
MIN_TAR_SIZE=5120000   # 5MB minimum expected compressed files size
BACKUP_DIR="${PWD}/backups"

# ------------------
# Functions
# ------------------
find_docker_container() {
    local search_string="$1"
    
    # Check Docker installation
    if ! command -v docker &>/dev/null; then
        echo "Error: Docker is not installed!" >&2
        return 1
    fi

    # Get all container names
    local containers
    containers=$(docker ps -a --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        echo "Error: No containers found!" >&2
        return 2
    fi

    # Find exact name matches
    local matches
    matches=$(grep -F -- "$search_string" <<< "$containers")
    
    if [ -z "$matches" ]; then
        echo "Error: No containers matching: '$search_string'" >&2
        return 3
    fi

    # Verify single match
    local match_count
    match_count=$(wc -l <<< "$matches")
    
    if [ "$match_count" -gt 1 ]; then
        echo "Error: Multiple containers matched:" >&2
        echo "$matches" >&2
        return 4
    fi

    if ! docker ps --filter "name=${matches}" --filter "status=running" | grep -q "${matches}"; then
        echo "Error: Container not running: $matches" >&2
        return 5
    fi

    # Output single matching container name
    echo "$matches"
}

check_container_storage() {
    echo "Checking storage usage in container: $CONTAINER_NAME"
    docker exec "$CONTAINER_NAME" df -h /var/lib/postgresql/data || {
        echo "ERROR: Failed to check container storage!" >&2
        exit 1
    }
}

list_active_connections() {
    docker exec "$CONTAINER_NAME" \
        psql -U postgres -d postgres -t\
        -c "SELECT pid, usename, datname, application_name, state, query_start, client_addr 
            FROM pg_stat_activity 
            WHERE pid <> pg_backend_pid()
            AND client_addr IS NOT NULL;"
#            AND state = 'active'
#            AND usename NOT IN ('postgres', 'replicator')
}

terminate_connections() {
    local pids=$1
    for pid in $pids; do
        echo "Terminating PID $pid..."
        docker exec "$CONTAINER_NAME" \
            psql -U postgres -d postgres \
            -c "SELECT pg_terminate_backend($pid)" >/dev/null 2>&1
            
        if [ $? -eq 0 ]; then
            echo "Successfully terminated: $pid"
        else
            echo "ERROR: Failed to terminate $pid" >&2
        fi
    done
}

confirm_action() {
    local message="$1"
    read -p "${message} (y/n) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

list_active_connection_pids() {
    list_active_connections | awk 'NR>=1 && NF>0 {print $1}'
}

check_connections() {
    echo "Searching for active connections..."
    connections=$(list_active_connections)
    
    if [ -z "$connections" ]; then
        echo "No active connections to terminate"
        return 0
    fi

    while true; do
        echo "==== Active Connections ===="
        echo "$connections"
        echo "==========================="

        if ! confirm_action "Are you sure you want to terminate these connections?"; then
            echo "Continuing without termination"
            return 1
        fi

        pids=$(echo "$connections" | awk 'NR>=1 {print $1}')
        terminate_connections "$pids"

        echo "Verifying termination..."
        remaining=$(list_active_connection_pids | wc -l)

        if [ "$remaining" -gt 0 ]; then
            echo "Warning: ${remaining} connections still active"
            
            if ! confirm_action "Would you like to retry termination?"; then
                echo "Proceeding with active connections"
                return 1
            fi
            
            connections=$(list_active_connections)
            continue
        else
            echo "Termination completed successfully"
            break
        fi
    done
}

check_file_size() {
    local file_path="$1"
    local min_size="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "ERROR: File does not exist: $file_path" >&2
        exit 1
    fi
    
    local actual_size=$(wc -c < "$file_path")
    if [ "$actual_size" -lt "$min_size" ]; then
        echo "ERROR: File size suspiciously small: $file_path" >&2
        echo "       Expected minimum: $min_size bytes, Actual: $actual_size bytes" >&2
        exit 1
    fi
}

container_cleanup() {
    local container_name="$1"
    local sql_file="$2"
    local tar_file="$3"
    
    echo "Cleaning up container files..."
    docker exec "$container_name" rm -f "/home/$sql_file" || {
        echo "WARNING: Failed to delete SQL dump from container" >&2
    }
    docker exec "$container_name" rm -f "/home/$tar_file" || {
        echo "WARNING: Failed to delete compressed files from container" >&2
    }
}

validate_checksum() {
    local src="$1"
    local dest="$2"
    
    echo "Validating file integrity..."
    container_sum=$(docker exec "$CONTAINER_NAME" sha256sum "/home/$src" | cut -d' ' -f1)
    host_sum=$(sha256sum "$dest" | cut -d' ' -f1)
    
    if [ "$container_sum" != "$host_sum" ]; then
        echo "CRITICAL ERROR: Checksum mismatch for $src" >&2
        echo "Container: ${container_sum:0:12}... Host: ${host_sum:0:12}..." >&2
        exit 1
    fi
}

# ------------------
# Terminate active connections
# ------------------
# Container name searching
CONTAINER_NAME=$(find_docker_container "$DB_NAME_SUBSTRING") || exit $?
echo "Found container: $CONTAINER_NAME"

check_container_storage
if ! confirm_action "Are you sure you want to continue?"; then
    exit 1
fi
check_connections

# ------------------
# Backup process
# ------------------

# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
    exit 1
}

# Generate timestamp
DATE=$(date +"%Y%m%d_%H%M%S")

# File names
SQL_DUMP_FILE="sql_full_dump_${DATE}.sql"
COMPRESSED_DB_FILES="postgresql_files_${DATE}.tar.gz"
VERSION_FILE="postgresql_version.txt"

# Create SQL dump
echo "Creating SQL dump..."
docker exec -t "$CONTAINER_NAME" bash -c \
    "pg_dumpall -U postgres --clean > /home/$SQL_DUMP_FILE" || {
    echo "ERROR: pg_dumpall failed!" >&2
    exit 1
}

# Copy SQL dump to host
docker cp "$CONTAINER_NAME:/home/$SQL_DUMP_FILE" "$BACKUP_DIR/" || {
    echo "ERROR: Failed to copy SQL dump!" >&2
    exit 1
}

# Compress database files
echo "Compressing database files..."
docker exec -t "$CONTAINER_NAME" bash -c \
    "tar -czf /home/$COMPRESSED_DB_FILES -C /var/lib/postgresql/data . -C /etc/postgresql ." || {
    echo "ERROR: Compression failed!" >&2
    exit 1
}

# Copy compressed files to host
docker cp "$CONTAINER_NAME:/home/$COMPRESSED_DB_FILES" "$BACKUP_DIR/" || {
    echo "ERROR: Failed to copy compressed files!" >&2
    exit 1
}

# Get PostgreSQL version
PG_VERSION=$(docker exec -t "$CONTAINER_NAME" psql -U postgres -c "SELECT version();" -t | tr -d ' ' | tr -d '\n')
echo "$PG_VERSION" > "${BACKUP_DIR}/$VERSION_FILE" || {
    echo "ERROR: Failed to save version info!" >&2
    exit 1
}

# Verify file sizes
echo "Verifying backup integrity..."
check_file_size "${BACKUP_DIR}/$SQL_DUMP_FILE" $MIN_SQL_SIZE
check_file_size "${BACKUP_DIR}/$COMPRESSED_DB_FILES" $MIN_TAR_SIZE
check_file_size "${BACKUP_DIR}/$VERSION_FILE" 20

# Safe container cleanup after successful backup
validate_checksum "$SQL_DUMP_FILE" "${BACKUP_DIR}/$SQL_DUMP_FILE"
validate_checksum "$COMPRESSED_DB_FILES" "${BACKUP_DIR}/$COMPRESSED_DB_FILES"
container_cleanup "$CONTAINER_NAME" "$SQL_DUMP_FILE" "$COMPRESSED_DB_FILES"

echo "Backup completed successfully and container cleaned!"
echo "Files saved in: $BACKUP_DIR"
echo "- SQL dump: $SQL_DUMP_FILE"
echo "- Compressed DB files: $COMPRESSED_DB_FILES"
echo "- Version info: $VERSION_FILE"
