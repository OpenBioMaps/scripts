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
# Input:
#  - Docker container name: Can be provided as parameter or uses default
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
DEFAULT_CONTAINER_NAME="obm-composer_biomaps_db_1"
MIN_SQL_SIZE=102400    # 100KB minimum expected SQL dump size
MIN_TAR_SIZE=5120000   # 5MB minimum expected compressed files size
BACKUP_DIR="${PWD}/backups"

# ------------------
# Functions
# ------------------
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

verify_container() {
    if ! docker inspect "$1" &>/dev/null; then
        echo "ERROR: Container '$1' not found!" >&2
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
# Main backup process
# ------------------
# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
    exit 1
}

# Container name handling
CONTAINER_NAME=${1:-$DEFAULT_CONTAINER_NAME}
verify_container "$CONTAINER_NAME"

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
