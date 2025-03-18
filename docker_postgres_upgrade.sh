#!/bin/bash

## PostgreSQL Docker Container Upgrade Script
# Purpose: Semiautomated upgrade solution for PostgreSQL databases in Docker containers
# Features:
# - Creates SQL dump and compressed data directory backup
# - Comprehensive integrity checks (file size, checksum validation)
# - Container cleanup after successful backup
# - Error handling with immediate failure on critical issues
# - Configurable minimum file sizes and container name
# - Locate the database service within a docker-compose.yml file
#   specifically using the values defined in the DB_SERVICE_SEARCH_STRINGS
# - Modifying images, add or modify database named volume and check other named volumes in docker-compose file
# - Bring down and up Docker Compose when necessary (after confirmation)
# - Restore dump file to the database container
# - Run validation queries
#
# Output files:
#  1. SQL dump file: sql_full_dump_YYYYMMDD_HHMMSS.sql
#  2. Compressed database files: postgresql_files_YYYYMMDD_HHMMSS.tar.gz
#  3. PostgreSQL version info: postgresql_version_YYYYMMDD_HHMMSS.txt
#  4. Docker-compose file: docker-compose.yml_YYYYMMDD_HHMMSS
#  5. Database restore log file: db_restore_YYYYMMDD_HHMMSS.log
#
# File locations:
#  - Inside container: Created in /home/ directory
#  - Host system: Copied to backups directory in the script's current working directory
#
# Notes:
#  - --clean option in pg_dumpall: Adds DROP statements before each object
#    to enable clean reinstall by removing existing objects


#set -euo pipefail
#set -xeo pipefail 

# ------------------
# Configuration
# ------------------
DB_USER="biomapsadmin"
DB_SERVICE_SEARCH_STRINGS=$'openbiomaps/database
openbiomaps/web-app:pg
openbiomaps/web-app:11-
openbiomaps/web-app:13-'
DB_IMAGE="registry.gitlab.com/openbiomaps/web-app:pg15-3.5"
APP_IMAGE="registry.gitlab.com/openbiomaps/web-app:latest"
MAPSERVER_IMAGE="registry.gitlab.com/openbiomaps/web-app:mapserver"
PG_NEW_VOLUME="pg15_data"
DB_TARGET_PATH="/var/lib/postgresql/data"
MIN_SQL_SIZE=204800    # 200KB minimum expected SQL dump size (greater than the empty biomaps_db database)
MIN_TAR_SIZE=5120000   # 5MB minimum expected compressed files size
BACKUP_DIR="${PWD}/backups"
DATE=$(date +"%Y%m%d_%H%M%S")
SQL_DUMP_FILE="sql_full_dump_${DATE}.sql"
VERSION_FILE="postgresql_version_${DATE}.txt"
COMPRESSED_DB_FILES="postgresql_files_${DATE}.tar.gz"
SQL_TEST_IN_PROD_DB_FILENAME="sql_test_in_PROD_db.txt"
SQL_TEST_IN_TEST_DB_FILENAME="sql_test_in_TEST_db.txt"
SQL_TEST_IN_NEW_DB_FILENAME="sql_test_in_NEW_db.txt"



# ------------------
# Functions
# ------------------
find_docker_container() {
    local search_string
    # Only the first row
    read -r search_string <<< "$1"
# echo "search_string: $search_string" >&2
    
    # Check Docker installation
    if ! command -v docker &>/dev/null; then
        echo "Error: Docker is not installed!" >&2
        return 1
    fi

    # Initialize containers variable
    local containers=$(docker ps -a --format "{{.Names}}")

    # If no containers found, ask to start them
    if [ -z "$containers" ]; then
        echo "Error: No containers found!" >&2
        if confirm_action "Can I run docker-compose up -d command?"; then
            echo "Running docker-compose up -d command..." >&2
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d
        else
            echo "Operation cancelled by user." >&2
            return 1
        fi
    fi

    local max_attempts=20
    local attempt=0
    # Start a loop that continues until containers are found
    while [ -z "$containers" ]; do
        # Get all container names
        containers=$(docker ps -a --format "{{.Names}}")
        if [ $attempt -ge $max_attempts ]; then
            echo "Error: PostgreSQL did not become ready after $max_attempts attempts." >&2
            exit 1
        fi
        echo "\nAttempt $attempt: PostgreSQL is not ready. Retrying in 1 seconds..." >&2
        sleep 1
        attempt=$((attempt+1))
    done

    # Find exact name matches
    local matches
    matches=$(grep -F -- "$search_string" <<< "$containers")
# echo "matches: $matches" >&2
    if [ -z "$matches" ]; then
        echo "Error: No containers matching: '$search_string'" >&2
        if confirm_action "Can I run docker-compose up -d command?"; then
            echo "Running docker-compose up -d command..." >&2
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d
        fi
    fi

    local max_attempts=20
    local attempt=0
    # Start a loop that continues until matches are found
    while [ -z "$matches" ]; do
        containers=$(docker ps -a --format "{{.Names}}")
        matches=$(grep -F -- "$search_string" <<< "$containers")
        if [ $attempt -ge $max_attempts ]; then
            echo "Error: PostgreSQL container did not become ready after $max_attempts attempts." >&2
            exit 1
        fi
        printf "Attempt %d: PostgreSQL container is not ready. Retrying in 1 seconds...\r" "$attempt" >&2
        sleep 1
        attempt=$((attempt+1))
    done

    # Verify single match
    local match_count
    match_count=$(wc -l <<< "$matches")
    
    if [ "$match_count" -gt 1 ]; then
        echo "Error: Multiple containers matched:" >&2
        echo "$matches" >&2
        return 4
    fi
    # Check if container is running
    if ! docker ps --filter "name=${matches}" --filter "status=running" | grep -q "${matches}"; then
        echo "Error: Container not running: $matches" >&2
        
        # Interactive confirmation
        if ! confirm_action "Are you sure you want to start the container?"; then
            echo "" >&2
            return 0
        fi

        # Start the container
        echo "" >&2
        echo "Starting container..." >&2
        if ! docker start "${matches}" >/dev/null; then
            echo "Failed to start container" >&2
            return 6
        fi

        # Wait for PostgreSQL to become ready
        echo "Waiting for PostgreSQL to become ready" >&2
        sleep 5
        local timeout=60  # 60 seconds timeout
        while ! docker exec "$matches" pg_isready -U $DB_USER -h localhost >/dev/null 2>&1; do
            sleep 2
            ((timeout-=2))
            echo -n "."  >&2
            
            if [ $timeout -le 0 ]; then
                echo -e "\nTimeout waiting for PostgreSQL" >&2
                return 7
            fi
        done
        echo -e "\nPostgreSQL is ready!"  >&2
    fi

    # Output single matching container name
    echo -n "$matches"
}

check_container_storage() {
    echo "Checking storage usage in container: $CONTAINER_NAME"
    docker exec "$CONTAINER_NAME" df -h / || {
        echo "ERROR: Failed to check container storage!" >&2
        exit 1
    }
    echo -n "Storage space consumed by database files: "
    docker exec "$CONTAINER_NAME" du -sh /var/lib/postgresql/data || {
        echo "ERROR: Failed to check container storage!" >&2
        exit 1
        }
}

list_active_connections() {
    docker exec "$CONTAINER_NAME" \
        psql -U $DB_USER -d postgres -t\
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
            psql -U $DB_USER -d postgres \
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
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
    # [[ $REPLY =~ ^[Yy]$ ]]
}

list_active_connection_pids() {
    list_active_connections | awk 'NR>=1 && NF>0 {print $1}'
}

stop_connections() {
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
    local file="$2"
    
    echo "Cleaning up container files..."
    docker exec "$container_name" rm -f "/home/$file" || {
        echo "WARNING: Failed to delete $file from container" >&2
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

sql_full_dump(){
    # File names
    local sql_dump_file="$1"
    local VERSION_FILE="$2"

    # Check existing SQL dumps
#     shopt -s nullglob
#         latest_sql=$(ls -t $BACKUP_DIR/*.sql 2>/dev/null | head -n1)
#     shopt -u nullglob
# echo "latest_sql: $latest_sql" >&2
# echo "BACKUP_DIR: $BACKUP_DIR" >&2
#     if [[ "$latest_sql" == "$BACKUP_DIR" ]]; then
#         latest_sql=""
#     fi


if [ -n "$(find $BACKUP_DIR -name "*.sql" 2>/dev/null)" ]; then
    latest_sql=$(ls -t $BACKUP_DIR/*.sql 2>/dev/null | head -n1)
else
    latest_sql=""
fi



    if [[ -n "$latest_sql" ]]; then
        echo 
        echo "Latest SQL backup: $latest_sql"
        if ! confirm_action "Create new SQL dump?"; then
            SQL_DUMP_FILE=$(basename $latest_sql)
            return
        fi
    fi

    # Create SQL dump
    echo
    echo "--------------------"
    echo "Creating SQL dump..."
    echo "--------------------"

    set +e
    docker exec -t "$CONTAINER_NAME" bash -c \
        "pg_dumpall -U $DB_USER --clean > /home/$sql_dump_file" & dump_pid=$!

    # Get total size of files to backup for progress calculation
    total_size=$(docker exec -t "$CONTAINER_NAME" bash -c "du -sb /var/lib/postgresql/data | awk '{sum+=\$1} END {printf \"%d\", sum}'" | tr -cd '0-9')

    # Display progress indicator for backup
    while kill -0 $dump_pid 2>/dev/null; do
        current_size=$(docker exec -t "$CONTAINER_NAME" bash -c "stat -c %s /home/$sql_dump_file 2>/dev/null || printf \"%d\" 0")
        current_size_mb=$(( $(echo "$current_size" | tr -cd '0-9') / 1024 / 1024 ))
        printf "\rBackuped: %d MB" "$current_size_mb"
        sleep 0.3
    done
    echo

    wait $dump_pid
    dump_status=$?
    if [ $dump_status -ne 0 ]; then
        echo "ERROR: pg_dumpall failed!" >&2
        exit 1
    fi
    # set -e

    # docker exec -t "$CONTAINER_NAME" bash -c \
    #     "pg_dumpall -U $DB_USER --clean > /home/$sql_dump_file" || {
    #     echo "ERROR: pg_dumpall failed!" >&2
    #     exit 1
    # }

    # Get file size for progress calculation
    file_size=$(docker exec -t "$CONTAINER_NAME" bash -c "stat -c %s /home/$sql_dump_file 2>/dev/null | awk '{printf \"%d\", \$1}'" | tr -cd '0-9')

    # Copy file from container to host
    docker cp "$CONTAINER_NAME:/home/$sql_dump_file" "${BACKUP_DIR}/" & copy_pid=$!

    # Display progress indicator for copying
    while kill -0 $copy_pid 2>/dev/null; do
        # Check the size of the file being copied
        copied_size=$(stat -c %s "${BACKUP_DIR}/$sql_dump_file" 2>/dev/null || echo 0)
        copied_size=$(echo "$copied_size" | tr -cd '0-9')
        copied_size_mb=$(( copied_size / 1024 / 1024 ))
        percentage=$(( copied_size * 100 / file_size ))
        
        # Progress bar
        printf "\rCopying: [%-50s] %d MB / %d MB (%d%%)\r" "$(printf '#%.0s' $(seq 1 $(( percentage / 2 ))))" "$copied_size_mb" "$(( file_size / 1024 / 1024 ))" "$percentage"
        sleep 0.3
    done


    # # Copy SQL dump to host
    # docker cp "$CONTAINER_NAME:/home/$sql_dump_file" "$BACKUP_DIR/" || {
    #     echo "ERROR: Failed to copy SQL dump!" >&2
    #     exit 1
    # }

    # Get PostgreSQL version
    echo "Getting PostgreSQL version..."
    PG_VERSION=$(docker exec -i "$CONTAINER_NAME" psql -U $DB_USER -d postgres -c "SELECT version();" -t 2>&1)
    echo "PG verzió: $PG_VERSION"
    echo "$PG_VERSION" > "${BACKUP_DIR}/$VERSION_FILE" || {
        echo "ERROR: Failed to save version info!" >&2
        exit 1
    }

    # Verify file sizes
    echo "Verifying backup integrity..."
    check_file_size "${BACKUP_DIR}/$sql_dump_file" $MIN_SQL_SIZE
    check_file_size "${BACKUP_DIR}/$VERSION_FILE" 20

    # Safe container cleanup after successful backup
    validate_checksum "$SQL_DUMP_FILE" "${BACKUP_DIR}/$sql_dump_file"
    container_cleanup "$CONTAINER_NAME" "$SQL_DUMP_FILE"

    echo
    echo "--------------------------------------------------"
    echo "Dump completed successfully and container cleaned!"
    echo "--------------------------------------------------"
    echo "Files saved in: $BACKUP_DIR"
    echo "- SQL dump: $sql_dump_file"
    echo "- Version info: $VERSION_FILE"
}

db_files_backup(){
    # Check existing file backups
    # shopt -s nullglob
    # latest_file_backup=$(ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null | head -n1)
    # shopt -u nullglob
    # if [[ "$latest_file_backup" == "$BACKUP_DIR" ]]; then
    #     latest_file_backup=""
    # fi

if [ -n "$(find $BACKUP_DIR -name "*.tar.gz" 2>/dev/null)" ]; then
    latest_file_backup=$(ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null | head -n1)
else
    latest_file_backup=""
fi

    if [[ -n "$latest_file_backup" ]]; then
        echo
        echo "Latest files backup: $latest_file_backup"
        if ! confirm_action "Create new files backup?"; then
            return
        fi
    fi

    # Compress database files with progress indication
    echo "Compressing database files..."
    
    # Get total size of files to be compressed for progress calculation
    total_size=$(docker exec -t "$CONTAINER_NAME" bash -c "du -sb /var/lib/postgresql/data /etc/postgresql | awk '{sum+=\$1} END {printf \"%d\", sum}'" | tr -cd '0-9')

    set +e
    docker exec -t "$CONTAINER_NAME" bash -c \
        "tar -czf /home/$COMPRESSED_DB_FILES -C /var/lib/postgresql/data . -C /etc/postgresql ."  & compress_pid=$!

    # Display progress indicator for compressing
    while kill -0 $compress_pid 2>/dev/null; do
        current_size=$(docker exec -t "$CONTAINER_NAME" bash -c "stat -c %s /home/$COMPRESSED_DB_FILES 2>/dev/null || printf \"%d\" 0")
        current_size_mb=$(( $(echo "$current_size" | tr -cd '0-9') / 1024 / 1024 ))
        printf "\rCompressed: %d MB" "$current_size_mb"
        sleep 0.3
    done
    echo

    wait $compress_pid
    status=$?
    if [ $status -ne 0 ]; then
        echo "ERROR: Compression failed!" >&2
        exit 1
    fi
    # set -e

    # Copy to host with progress indicator
    echo "Copying compressed files to host..."

    # Get file size for progress calculation
    file_size=$(docker exec -t "$CONTAINER_NAME" bash -c "stat -c %s /home/$COMPRESSED_DB_FILES 2>/dev/null | awk '{printf \"%d\", \$1}'" | tr -cd '0-9')

    # Copy file from container to host
    docker cp "$CONTAINER_NAME:/home/$COMPRESSED_DB_FILES" "${BACKUP_DIR}/$COMPRESSED_DB_FILES" & copy_pid=$!

    # Display progress indicator for copying
    while kill -0 $copy_pid 2>/dev/null; do
        # Check the size of the file being copied
        copied_size=$(stat -c %s "${BACKUP_DIR}/$COMPRESSED_DB_FILES" 2>/dev/null || echo 0)
        copied_size=$(echo "$copied_size" | tr -cd '0-9')
        copied_size_mb=$(( copied_size / 1024 / 1024 ))
        percentage=$(( copied_size * 100 / file_size ))
        
        # Progress bar
        printf "\rCopying: [%-50s] %d MB / %d MB (%d%%)\r" "$(printf '#%.0s' $(seq 1 $(( percentage / 2 ))))" "$copied_size_mb" "$(( file_size / 1024 / 1024 ))" "$percentage"
        sleep 0.3
    done

    # Verify file sizes
    echo "Verifying backup integrity..."
    check_file_size "${BACKUP_DIR}/$COMPRESSED_DB_FILES" $MIN_TAR_SIZE

    # Safe container cleanup after successful backup
    validate_checksum "$COMPRESSED_DB_FILES" "${BACKUP_DIR}/$COMPRESSED_DB_FILES"
    container_cleanup "$CONTAINER_NAME" "$COMPRESSED_DB_FILES"

    echo "-------------------------------------------------------------------"
    echo "Database files backup completed successfully and container cleaned!"
    echo "-------------------------------------------------------------------"
    echo "File saved in: $BACKUP_DIR"
    echo "- Compressed DB files: $COMPRESSED_DB_FILES"
}

# db_files_backup(){

#     # Check existing file backups
#     latest_file_backup=$(ls -t backups/*.tar.gz 2>/dev/null | head -n1)
#     if [[ -n "$latest_file_backup" ]]; then
#         echo
#         echo "Latest files backup: $latest_file_backup"
#         if ! confirm_action "Create new files backup?"; then
#             return
#         fi
#     fi

#     # Compress database files
#     echo "Compressing database files..."
#     docker exec -t "$CONTAINER_NAME" bash -c \
#         "tar -czf /home/$COMPRESSED_DB_FILES -C /var/lib/postgresql/data . -C /etc/postgresql ." || {
#         echo "ERROR: Compression failed!" >&2
#         exit 1
#     }

#     # Copy compressed files to host
#     docker cp "$CONTAINER_NAME:/home/$COMPRESSED_DB_FILES" "$BACKUP_DIR/" || {
#         echo "ERROR: Failed to copy compressed files!" >&2
#         exit 1
#     }

#     # Verify file sizes
#     echo "Verifying backup integrity..."
#     check_file_size "${BACKUP_DIR}/$COMPRESSED_DB_FILES" $MIN_TAR_SIZE

#     # Safe container cleanup after successful backup
#     validate_checksum "$COMPRESSED_DB_FILES" "${BACKUP_DIR}/$COMPRESSED_DB_FILES"
#     container_cleanup "$CONTAINER_NAME" "$COMPRESSED_DB_FILES"

#     echo "-------------------------------------------------------------------"
#     echo "Database file backup completed successfully and container cleaned!"
#     echo "-------------------------------------------------------------------"
#     echo "File saved in: $BACKUP_DIR"
#     echo "- Compressed DB files: $COMPRESSED_DB_FILES"
# }

show_help() {
    echo 
    echo "OpenBioMaps semiautomated PostgreSQL upgrade in docker"
    echo 
    echo "Usage: $0 <command> [db_container_name]"
    echo ""
    echo " • Locate the database service within a docker-compose.yml file (using a DB_SERVICE_SEARCH_STRINGS)."
    echo " • Verifies storage status and then prompts the user for confirmation before proceeding."
    echo ""
    echo "Commands:"
    echo "  testupgrade:  Performs a test upgrade without stopping live services (e.g., Apache or PostgreSQL)."
    echo "                • Creates a database dump from the production database without performing a full data directory backup."
    echo "                • Starts a temporary test container (named 'pg-test') using the specified PostgreSQL image."
    echo "                • Restores the dump file into the test container and then runs validation queries on both"
    echo "                  the test container and the production database dump to compare their outputs."
    echo "                • If differences are detected,the script will output the differences."
    echo ""
    echo "  upgrade:      Performs a production upgrade after user confirmation."
    echo "                • Closes active connections and stops live services (e.g., Apache and PostgreSQL)"
    echo "                  after receiving explicit user approval."
    echo "                • Creates a full database dump and a backup of the data directory."
    echo "                • Stop all containers (docker-compose down) and updates Docker Compose settings (new pgdata volume, gitlab image)."
    echo "                • Check if named volumes exist in the docker-compose configuration."
    echo "                • Restore dump file and run validation queries."
    echo "                • This mode should be used only after successful testing with the 'testupgrade' command."
}

run_sql_query() {
  local container="$1"
  local db_user="$2"
  local database="$3"
  local query="$4"
  local output_file="${5:-}"

  # Execute the SQL query in the Docker container and capture any output or error
  local result
  result=$(docker exec "$container" psql -U "$db_user" -d "$database" -c "$query" 2>&1)
  local status=$?

  # If the command fails, output an error message along with the error details
  if [ $status -ne 0 ]; then
      echo "Error: Failed to execute the SQL query." >&2
      echo "Details: $result" >&2
      return $status
  fi

  # If output file exists, append the result; otherwise, create a new file
  if [ -n "$output_file" ]; then
      if [ -f "$output_file" ]; then
        #   echo "$result" | tee -a "$output_file"
        echo "$result" >> "$output_file"

      else
        #   echo "$result" | tee "$output_file"
        echo "$result" > "$output_file"
      fi
  else
      echo "$result"
  fi
}

run_test_script() {
    # This script defines the function "run_test_script", which executes a series of SQL queries against a PostgreSQL database
    # running in a Docker container. I
    # The function performs the following actions:
    #   1. Runs an ANALYZE command to update the database statistics.
    #   2. Retrieves the top 20 tables from the "public" schema, ordering them by their estimated number of rows.
    #   3. Extracts the table name with the most rows by processing the result (taking the 3rd line and removing spaces).
    #   4. Runs a query to return 20 rows from that table

  local container="$1"
  local db_user="$2"
  local database="$3"
  local output_file="${4:-}"

  # Run ANALYZE; command to update the database statistics.
  run_sql_query "$container" "$db_user" "$database" "ANALYZE;"

  # SQL query to retrieve the top 20 tables from the public schema.
  sql_query=$(cat <<'EOF'
SELECT 'Top Tables' AS type,
       relname AS table_name,
       reltuples::bigint AS row_count
FROM pg_class
WHERE relnamespace = (
  SELECT oid
  FROM pg_namespace
  WHERE nspname = 'public'
)
  AND relkind = 'r'
ORDER BY reltuples DESC, relname ASC
LIMIT 20;
EOF
)
  run_sql_query "$container" "$db_user" "$database" "$sql_query" "$output_file"
  # Alternative call:
  # run_sql_query "$container" "$db_user" "$database" "SELECT 'Top Tables' AS type, relname AS table_name, reltuples::bigint AS row_count FROM pg_class WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public') AND relkind = 'r' ORDER BY reltuples DESC LIMIT 20" "$output_file"

  # Get the table name with the most rows (estimated).
  sql_query=$(cat <<'EOF'
SELECT relname AS table_name
FROM pg_class
WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND relkind = 'r'
ORDER BY reltuples DESC
LIMIT 1;
EOF
)
  table_with_most_rows=$(run_sql_query "$container" "$db_user" "$database" "$sql_query" | sed -n '3p' | tr -d ' ')
  
  # SQL query to select 20 rows from the table with the most rows.
  sql_query=$(cat <<EOF
SELECT *
FROM ${table_with_most_rows}
LIMIT 20;
EOF
)
  run_sql_query "$container" "$db_user" "$database" "$sql_query" "$output_file"
}

wait_for_postgres() {
  local container="$1"
  local db_user="$2"
  local db_name="$3"
  local max_attempts="${4:-10}"
  local sleep_interval="${5:-3}"
# echo "container: $container"
# echo "db_user: $db_user"
# echo "db_name: $db_name"
# echo "max_attempts: $max_attempts"
# echo "sleep_interval: $sleep_interval"

  echo "Waiting for PostgreSQL to be ready in container '$container' (User: $db_user, Database: $db_name)..."

  local attempt=1

  while true; do
    # Run the pg_isready command inside the container.
    docker exec "$container" pg_isready -U "$db_user" -d "$db_name" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      sleep 15
      echo "PostgreSQL is ready!"
      break
    else
      if [ $attempt -ge $max_attempts ]; then
        echo "Error: PostgreSQL did not become ready after $max_attempts attempts." >&2
        return 1
      fi
      echo "Attempt $attempt: PostgreSQL is not ready. Retrying in $sleep_interval seconds..."
      sleep "$sleep_interval"
      attempt=$((attempt+1))
    fi
  done
}

# Detect Docker Compose command (V1 vs V2)
detect_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"  # V1 or V2
    else
        echo "docker compose"  # V2 Docker CLI Plugin
    fi
}

# Find YAML file in priority order
find_compose_file() {
    local files=("docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml")
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "$file"
            return 0
        fi
    done
    return 1
}

# Check if a service exists
service_exists() {
    local service="$1"
    $COMPOSE_CMD -f "$COMPOSE_FILE" config --services 2>/dev/null | grep -qw "^$service$"
    return $?
}

get_docker_project_prefix() {
    local compose_file=$1
    local compose_dir
    local dir_name
    local project_name

    # Use environment variable if set and non-empty
    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
        project_name="${COMPOSE_PROJECT_NAME}"
    else
        # Resolve absolute path to get proper directory name
        compose_dir=$(dirname "$(realpath "$compose_file")")
        dir_name=$(basename "$compose_dir")
        project_name="${dir_name}"
    fi

    # Sanitize the project name
    project_name=$(echo "${project_name}" | \
        tr '[:upper:]' '[:lower:]' | \
        tr -cd '[:alnum:]_' | \
        sed -E 's/^[^a-z0-9]*//; s/_+$//')

    echo "${project_name}"
}

extract_volume_from_compose() {
    local yaml_file=$1
    local target_path=$2
    
    # Parse YAML with simple regex (for basic cases)
    local volume_raw=$(grep -E "^\s*-\s*[^:]+:$target_path" "$yaml_file" | head -n1)
# echo "Raw volume definition: '$volume_raw'" >&2 
    if [[ -z "$volume_raw" ]]; then
        echo
        echo "Error: Volume definition not found for path '$target_path'" >&2
        return 0
    fi
    
    # Extract name (handles '"' characters as well)
    local volume_name=$(echo "$volume_raw" | \
        sed -E 's/^\s*-\s*("?)([^:"]+)\1:\s*\S+\s*(#.*)?$/\2/')

    echo "$volume_name"
}

find_volume_name() {
    local yaml_file=$1
    local volume project_prefix
    
    volume=$(extract_volume_from_compose "$yaml_file" "$DB_TARGET_PATH") || return 0
    
    # Determine project prefix
    project_prefix=$(get_docker_project_prefix "$yaml_file")
    
    # Check for external volume (name contains '.' or '_')
    if [[ "$volume" =~ [._] ]]; then
        echo "$volume" # External volume, no prefix
    else
        echo "${project_prefix}_${volume}" # Project-specific volume
    fi
}

verify_volume_copy() {
    local original_vol=$1
    local backup_vol=$2

    echo "Verifying the copy..." >&2
    # Get sizes
    original_size=$(docker run --rm -v "$original_vol":/vol alpine du -sh /vol | awk '{print $1}')
    backup_size=$(docker run --rm -v "$backup_vol":/vol alpine du -sh /vol | awk '{print $1}')
    echo "Original volume size: $original_size" >&2
    echo "Backup volume size: $backup_size" >&2

    if docker run --rm \
            -v "$backup_vol":/vol1 \
            -v "$original_vol":/vol2 \
            alpine ash -c \
            'diff -r /vol1 /vol2' >/dev/null; then
        echo "The contents of the volumes are IDENTICAL" >&2
        return 0
    else
        echo "The contents of the volumes are DIFFERENT" >&2
        return 1
    fi
}

compare_volumes() {
    local vol1=$1
    local vol2=$2

    if ! docker volume inspect "$vol1" &>/dev/null; then
        echo "Error: Volume $vol1 does not exist!" >&2
        return 2
    fi

    if ! docker volume inspect "$vol2" &>/dev/null; then
        echo "Error: Volume $vol2 does not exist!" >&2
        return 2
    fi

    echo "Comparing contents of $vol1 and $vol2..."  >&2
    if docker run --rm \
        -v "$vol1":/vol1 \
        -v "$vol2":/vol2 \
        alpine ash -c \
        'diff -rq /vol1 /vol2' >/dev/null; then
        echo "Volume contents match."  >&2
        return 0
    else
        echo "Volume contents differ!"  >&2
        return 1
    fi
}

find_image_lines() {
    local yaml_file="$1"
    local service_search_string="$2"
    local result

    result=$(grep -n '^[[:space:]]*image:[[:space:]].*'"$service_search_string"'.*' "$yaml_file" | \
        sed 's/#.*$//')
    if [[ -z "$result" ]]; then
        # echo "No matching image lines found for '${service_search_string}' in '${yaml_file}'" >&2
        return 0
    fi

    echo "$result"
}

get_service_name_for_line() {
    local yaml_file="$1"
    local line_number="$2"
    local service_line
    service_line=$(head -n $((line_number - 1)) "$yaml_file" | \
                grep -E '^[[:space:]]*[a-zA-Z0-9_-]+:' | \
                grep -v -E '^[[:space:]]*services:' | \
                sed 's/#.*$//' | \
                tail -n 1)
                
    # If a service definition is found, strip leading spaces and the trailing colon.
    if [[ -n "$service_line" ]]; then
        echo "$service_line" | sed 's/^[[:space:]]*//' | sed 's/:[[:space:]]*$//'
    fi
}

get_data_services() {
    local yaml_file="$1"
    # Check if the file exists.
    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: File '$yaml_file' not found." >&2
        return 1
    fi

    # Find all image lines containing "$DB_SERVICE_SEARCH_STRINGS"
    local image_lines=""
    local found_line

    while IFS= read -r search_term; do
        # Skip empty lines
# echo "search_term: $search_term" >&2
        if [[ -n "$search_term" ]]; then
            found_line=$(find_image_lines "$yaml_file" "$search_term")
# echo "found_line: $found_line" >&2
            # Append found results if any exist
            if [[ -n "$found_line" ]]; then
                image_lines+="${found_line}"   #$'\n'
# echo "image_lines: $image_lines" >&2
            fi
        fi
    done <<< "$DB_SERVICE_SEARCH_STRINGS"

# echo "image_lines: $image_lines" >&2

    # For each matching image line, extract the associated service name safely.
    local line
    local service
    local all_services=""
    while IFS= read -r line; do
        # Extract the line number from the grep -n output (format: lineNum:content)
        local line_num
        line_num=$(echo "$line" | cut -d: -f1)
# echo "line_num: $line_num" >&2
        service=$(get_service_name_for_line "$yaml_file" "$line_num")
        if [[ -n "$service" ]]; then
            all_services+="$service"$'\n'
        fi
    done <<< "$image_lines"
    all_services="${all_services%$'\n'}"
# echo "all_services: $all_services" >&2

    # Output the list of unique service names.
    echo "$all_services" | sort -u
}

replace_image() {
    local yaml_file="$1"
    local line_number="$2"
    local new_image="$3"

    # Check: Does the YAML file exist?
    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: YAML file not found: $yaml_file"
        return 1
    fi

    # Check: Is the line number valid?
    if ! [[ "$line_number" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid line number: $line_number"
        return 1
    fi

    # Check if the 'image:' key exists in the specified line number
    local line_content
    line_content=$(sed -n "${line_number}p" "$yaml_file")
    if ! [[ "$line_content" =~ image: ]]; then
        echo "Error: 'image:' key not found in line $line_number."
        return 1
    fi

    # Replace the image in the specified line (inline comment will be deleted)
    sed -i "${line_number}s|image:.*|image: ${new_image}|" "$yaml_file"

    # Feedback
    echo "Successfully replaced the image in $yaml_file, line $line_number with: $new_image"
}

update_image() {
    local compose_file="$1"
    local search_string="$2"
    local new_image="$3"
    local image_lines line_num

    # Search for the image lines matching search_string
    image_lines=$(find_image_lines "$compose_file" "$search_string")
    
    # If any matching lines are found, proceed with replacement prompt
    if [[ -n "$image_lines" ]]; then
        # Retrieve the line number from the first match
        line_num=$(echo "$image_lines" | head -n 1 | cut -d: -f1)
        if [[ "$image_lines" == *"$new_image"* ]]; then
            echo "The new image [$new_image] is already in use. No changes needed."
            return
        fi
        if confirm_action "Do you want to replace the found [$image_lines] with [$new_image]?"; then
            replace_image "$compose_file" "$line_num" "$new_image"
        else
            echo "Image line replacement skipped."
        fi
    else
        echo "No matching image lines found for '$search_string' in '$compose_file'."
    fi
}

check_volume_exists() {
    local compose_file="$1"
    local volume_name="$2"

    # Array to store volume names defined in the Compose file.
    local defined_volumes=()
    local in_volumes=0
    local volumes_indent=0

    # Read the file line by line.
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comment lines starting with '#' (ignoring any leading whitespace)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect the beginning of the "volumes:" block.
        if [[ "$line" =~ ^[[:space:]]*volumes: ]]; then
            in_volumes=1
            volumes_indent=$(echo "$line" | sed 's/[^ \t].*//' | wc -c)
            continue
        fi

        # Process lines only if we're in the volumes block.
        if [[ $in_volumes -eq 1 ]]; then
            # Check if we've exited the volumes block
            current_indent=$(echo "$line" | sed 's/[^ \t].*//' | wc -c)
            if [[ $current_indent -le $volumes_indent ]] || [[ "$line" =~ ^[^[:space:]#] ]]; then
                in_volumes=0
                continue
            fi

            # Skip empty/commented lines
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue

            # Extract volume name (supports both named volumes and definitions)
            vol=$(echo "$line" | sed -E 's/^[[:space:]]*[-]?[[:space:]]*([^: #]+).*/\1/')
            defined_volumes+=("$vol")
        fi
    done < "$compose_file"

    # # Check volume presence
    count_in_volumes=$(printf '%s\n' "${defined_volumes[@]}" | grep -cxF "$volume_name")
    if [[ $count_in_volumes -eq 0 ]]; then
        echo
        echo "----------------------------------------------------------------"
        echo "Error: Volume '$volume_name' is NOT defined in the compose file!"
        echo "----------------------------------------------------------------"
        echo
    elif [[ $count_in_volumes -ge 2 ]]; then
        echo "Volume '$volume_name' is properly defined and used."
    else
        echo
        echo "--------------------------------------------------------------------------------"
        echo "Error: Volume '$volume_name' is NOT defined in SERVICES: or in VOLUMES: section!"
        echo "--------------------------------------------------------------------------------"
    fi

    # # Check Docker volume existence
    # local full_name="$(get_docker_project_prefix "$compose_file")_${volume_name}"
    # if ! docker volume inspect "$full_name" &>/dev/null; then
    #     echo "Error: Docker volume '$full_name' not found."
    # fi

    return 0
}

# check_volume_exists() {
#     local compose_file="$1"
#     local volume_name="$2"

#     # Array to store volume names defined in the Compose file.
#     local defined_volumes=()
#     local in_volumes=0
#     local volumes_indent=0

#     # Read the file line by line.
#     while IFS= read -r line || [[ -n "$line" ]]; do
#         # Skip comment lines starting with '#' (ignoring any leading whitespace)
#         if [[ "$line" =~ ^[[:space:]]*# ]]; then
#             continue
#         fi

#         # Detect the beginning of the "volumes:" block.
#         if [[ "$line" =~ ^[[:space:]]*volumes: ]]; then
#             in_volumes=1
#             # Calculate the indentation level of the volumes: line
# volumes_indent=$(echo "$line" | sed 's/[^ \t].*//' | wc -c)
#             continue
#         fi

#         # Process lines only if we're in the volumes block.
#         if [[ $in_volumes -eq 1 ]]; then
#             # Skip blank lines.
#             if [[ "$line" =~ ^[[:space:]]*$ ]]; then
#                 continue
#             fi

#             # Calculate current line indentation
# current_indent=$(echo "$line" | sed 's/[^ \t].*//' | wc -c)
            
#             # If the line has less or equal indentation than the volumes: line, 
#             # or it's a new top-level section (ending with a colon), 
#             # then the volumes block has ended
#             if [[ $current_indent -le $volumes_indent ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+: ]]; then
#                 in_volumes=0
#                 continue
#             fi

#             # Avoid lines that are commented out even after indentation.
#             if [[ "$line" =~ ^[[:space:]]*# ]]; then
#                 continue
#             fi

#             # Extract the volume name from the line (remove any trailing colon).
#             vol=$(echo "$line" | sed -E 's/^[[:space:]]+([^:]+):?.*/\1/')
#             defined_volumes+=("$vol")
#         fi
#     done < "$compose_file"

# echo "Defined volumes: ${defined_volumes[@]}" >&2

#     # Check if the specified volume is defined within the Compose file.
#     local volume_defined=false
#     for vol in "${defined_volumes[@]}"; do
# echo "Checking volume: $vol" >&2
#         if [[ "$vol" == "$volume_name" ]]; then
#             volume_defined=true
#             break
#         fi
#     done

#     if ! $volume_defined; then
#         echo
#         echo "----------------------------------------------------------------"
#         echo "Error: Volume '$volume_name' is NOT defined in the compose file."
#         echo "----------------------------------------------------------------"
#         echo
#         return 0
#     fi

#     # Retrieve the project prefix using the user-defined function.
#     local prefix
#     prefix=$(get_docker_project_prefix $compose_file)
    
#     # Compose the full volume name as Docker sets it (e.g., "project_volume").
#     local full_volume_name="${prefix}_${volume_name}"

#     # Check if the Docker volume with the full name exists.
#     if docker volume ls -q | grep -q "^${full_volume_name}$"; then
#         echo "Volume '$volume_name' is defined in the compose file and '$full_volume_name' exists in Docker."
#         return 0
#     else
#         echo 
#         echo "----------------------------------------------------------------------------------------------------"
#         echo "Error: Volume '$volume_name' is defined in the compose file but $full_volume_name does NOT exist in Docker."
#         echo "----------------------------------------------------------------------------------------------------"
#         echo
#         return 0
#     fi
# }

replace_volume() {
    local compose_file="$1"
    local old_volume="$2"
    local new_volume="$3"

    if ! confirm_action "Do you want to replace volume '$old_volume' with '$new_volume' in '$compose_file'?"; then
        echo "Operation cancelled."
        return 0
    fi
    sed -i -E "s/\b${old_volume}\b(:)/${new_volume}\1/g" "$compose_file"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to replace '$old_volume' with '$new_volume' in '$compose_file'."
        return 0
    fi

    echo "Successfully replaced volume '$old_volume' with '$new_volume' in '$compose_file'."
    return 0
}

list_service_lines() {
    local yaml_file="$1"
    local service_name="$2"

    # Find all occurrences of the service
    local service_matches=$(grep -n "^[[:space:]]*$service_name:" "$yaml_file")
    local match_count=$(echo "$service_matches" | wc -l)

    # Get the starting line of the first occurrence
    local start_line=$(echo "$service_matches" | head -1 | cut -d: -f1)

    if [[ -z "$start_line" ]]; then
        echo "Error: The specified service not found: $service_name"
        return 1
    fi

    # If multiple matches found, inform the user
    if [[ $match_count -gt 1 ]]; then
        echo "Note: Found $match_count occurrences of service '$service_name'. Using the first occurrence at line $start_line."
    fi

    # Determine the indentation level of the service
    local indent_level=$(sed -n "${start_line}p" "$yaml_file" | awk -F"$service_name:" '{print length($1)}')

    # Find the beginning of the next service or block
    # Only stop at non-comment lines with same or less indentation
    local next_service_line=$(tail -n +$((start_line + 1)) "$yaml_file" | 
                            grep -n "^[[:space:]]\{0,$indent_level\}[^[:space:]#]" | 
                            head -1 | 
                            cut -d: -f1)

    if [[ -z "$next_service_line" ]]; then
        # If there is no next service, go to the end of the file
        next_service_line=$(wc -l "$yaml_file" | awk '{print $1}')
    else
        # Add the start_line value because the indexing is shifted due to tail
        next_service_line=$((start_line + next_service_line))
    fi

    # Print the lines with original line numbers, excluding commented and empty lines
    for ((i=start_line; i<next_service_line; i++)); do
        line=$(sed -n "${i}p" "$yaml_file")
        # Skip commented lines and empty lines
        if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$(echo "$line" | tr -d '[:space:]')" ]]; then
            printf "%6d  %s\n" "$i" "$line"
        fi
    done
}

# Check if a volume exists in a service
volume_exists_in_service() {
    local compose_file="$1"
    local indent_spaces="$2"
    local volume_name="$3"
    local target_path="$4"
    
    grep -q "^${indent_spaces}- ${volume_name}:${target_path}" "$compose_file"
    return $?
}

# Check if a volume is defined in the top-level volumes section
volume_defined_in_top_level() {
    local compose_file="$1"
    local volume_name="$2"
    
    grep -q "^[[:space:]]*${volume_name}:" "$compose_file"
    return $?
}

# Add a volume to the top-level volumes section
add_to_top_level_volumes() {
    local compose_file="$1"
    local volume_name="$2"
    local temp_file="$3"
    
    # Check if top-level volumes section exists
    if ! grep -q "^volumes:" "$compose_file"; then
        # Add the top-level volumes section with the new volume
        echo "" >> "$temp_file"
        echo "volumes:" >> "$temp_file"
        echo "  ${volume_name}:" >> "$temp_file"
    else
        # Check if the volume is already defined in the top-level volumes section
        if ! volume_defined_in_top_level "$compose_file" "$volume_name"; then
            # Create another temporary file to add the volume to the top-level volumes section
            local temp_file2=$(mktemp)
            
            # Add the volume to the top-level volumes section
            cat "$temp_file" > "$temp_file2"
            
            # Find the top-level volumes section
            local volumes_section=$(grep -n "^volumes:" "$temp_file2" | cut -d: -f1)
            
            if [[ -n "$volumes_section" ]]; then
                # Insert after the volumes: line
                sed -i "${volumes_section}a\\  ${volume_name}:" "$temp_file2"
            else
                # Append to the end of the file
                echo "" >> "$temp_file2"
                echo "volumes:" >> "$temp_file2"
                echo "  ${volume_name}:" >> "$temp_file2"
            fi
            
            # Replace the first temp file with the second
            mv "$temp_file2" "$temp_file"
        fi
    fi
}

# Display confirmation message and changes
show_changes_and_confirm() {
    local service_indent="$1"
    local volume_name="$2"
    local target_path="$3"
    local is_new_section="$4"
    
    echo "The following changes will be made:"
    
    if [[ "$is_new_section" == "true" ]]; then
        local volumes_indent_spaces=$(printf "%${service_indent}s" "")
        local volume_entry_indent=$((service_indent + 2))
        local volume_entry_indent_spaces=$(printf "%${volume_entry_indent}s" "")
        
        echo "1. Add volumes section to service:"
        echo "${volumes_indent_spaces}volumes:"
        echo "${volume_entry_indent_spaces}- ${volume_name}:${target_path}"
    else
        echo "1. Add volume to service:"
        echo "${service_indent}- ${volume_name}:${target_path}"
    fi
    
    echo "2. Add volume to top-level volumes section:"
    echo "volumes:"
    echo "  ${volume_name}:"
    
    confirm_action "Do you want to proceed with these changes?"
}

# Main function to create a volume
create_volume() {
    local compose_file="$1"
    local service_name="$2"
    local new_volume_name="$3"
    local target_path="$4"
    
    echo "Checking service configuration for '$service_name' in '$compose_file'..."
    
    # Capture the output of list_service_lines
    local service_output=$(list_service_lines "$compose_file" "$service_name")
    
    # Display the current service configuration
    echo "$service_output"
    
    # Find the volumes section line number directly from the output
    local volumes_line=$(echo "$service_output" | grep "volumes:" | awk '{print $1}')
    
    if [[ -z "$volumes_line" ]]; then
        echo "Error: No 'volumes:' section found for service '$service_name'"
        
        # Ask if user wants to create a volumes section
        if confirm_action "Would you like to create a volumes section for this service?"; then
            # Get the last line number of the service from the output
            local last_line=$(echo "$service_output" | tail -1 | awk '{print $1}')
            
            # Get the indentation of the service line
            local service_line=$(echo "$service_output" | head -1 | awk '{print $1}')
            local service_content=$(sed -n "${service_line}p" "$compose_file")
            local service_indent=$(echo "$service_content" | awk -F"$service_name:" '{print length($1)}')
            
            # Calculate the indentation for volumes section (service indent + 2 spaces)
            local volumes_indent=$((service_indent + 2))
            local volumes_indent_spaces=$(printf "%${volumes_indent}s" "")
            
            # Calculate the indentation for volume entries (volumes indent + 2 spaces)
            local volume_entry_indent=$((volumes_indent + 2))
            local volume_entry_indent_spaces=$(printf "%${volume_entry_indent}s" "")
            
            # Create a temporary file with the new volumes section
            local temp_file=$(mktemp)
            
            # Add the volumes section with the new volume
            {
                head -n $last_line "$compose_file"
                echo "${volumes_indent_spaces}volumes:"
                echo "${volume_entry_indent_spaces}- ${new_volume_name}:${target_path}"
                echo ""
                tail -n +$((last_line + 1)) "$compose_file"
            } > "$temp_file"
            
            # Add to top-level volumes section
            add_to_top_level_volumes "$compose_file" "$new_volume_name" "$temp_file"
            
            # Ask for confirmation before making changes
            if show_changes_and_confirm "$volumes_indent_spaces" "$new_volume_name" "$target_path" "true"; then
                mv "$temp_file" "$compose_file"
                echo "Volume section created and new volume added successfully."
                echo "Updated service configuration:"
                list_service_lines "$compose_file" "$service_name"
            else
                rm "$temp_file"
                echo "Operation cancelled."
            fi
        else
            echo "Operation cancelled."
            return 1
        fi
    else
        # Get the indentation of the volumes line
        local volumes_content=$(sed -n "${volumes_line}p" "$compose_file")
        local volumes_indent=$(echo "$volumes_content" | awk -F"volumes:" '{print length($1)}')
        
        # Calculate the indentation for volume entries (volumes indent + 2 spaces)
        local volume_entry_indent=$((volumes_indent + 2))
        local volume_entry_indent_spaces=$(printf "%${volume_entry_indent}s" "")
        
        # Check if the volume already exists in the service
        if volume_exists_in_service "$compose_file" "$volume_entry_indent_spaces" "$new_volume_name" "$target_path"; then
            echo "Volume '${new_volume_name}:${target_path}' already exists for service '$service_name'"
            return 0
        fi
        
        # Create a temporary file with the new volume added
        local temp_file=$(mktemp)
        
        # Add the new volume entry after the volumes: line
        {
            head -n $volumes_line "$compose_file"
            echo "${volume_entry_indent_spaces}- ${new_volume_name}:${target_path}"
            tail -n +$((volumes_line + 1)) "$compose_file"
        } > "$temp_file"
        
        # Add to top-level volumes section
        add_to_top_level_volumes "$compose_file" "$new_volume_name" "$temp_file"
        
        # Ask for confirmation before making changes
        if show_changes_and_confirm "$volume_entry_indent_spaces" "$new_volume_name" "$target_path" "false"; then
            mv "$temp_file" "$compose_file"
            echo "New volume added successfully."
            echo "Updated service configuration:"
            list_service_lines "$compose_file" "$service_name"
        else
            rm "$temp_file"
            echo "Operation cancelled."
        fi
    fi
}

get_available_editor() {
    local editors=("nano" "vim" "cat")
    
    for editor in "${editors[@]}"; do
        if type "$editor" >/dev/null 2>&1; then
            echo "$editor"
            return 0
        fi
    done
    
    echo "Nem található szerkesztő"
    return 1
}

# Function to perform database restoration with progress monitoring
# Usage: restore_database_with_progress <sql_dump_file> <compose_command> <db_service> <db_user> <log_file>
restore_database_with_progress() {
    local sql_dump_file="$1"
    local compose_cmd="$2"
    local db_service_name="$3"
    local db_user="$4"
    local log_file="$5"
    
    if [ ! -f "$sql_dump_file" ]; then
        echo "Error: SQL dump file not found: $sql_dump_file" >&2
        return 1
    fi
    
    wait_for_postgres $CONTAINER_NAME $DB_USER "postgres" 10 3

    echo "Starting database restoration..."
    
    # Start the restoration process in the background
    # set +e
    if [[ "$compose_cmd" == "docker" ]]; then
        (cat "$sql_dump_file" | $compose_cmd exec -i $db_service_name psql -U $db_user postgres > "$log_file" 2> >(tee -a "$log_file" >&2)) & local restore_pid=$!
    else
        (cat "$sql_dump_file" | $compose_cmd exec -T $db_service_name psql -U $db_user postgres > "$log_file" 2> >(tee -a "$log_file" >&2)) & local restore_pid=$!
    fi
    # Display progress indicator
    local start_time=$(date +%s)
    echo "Restoration in progress..."
    echo "Time  - Log lines"
    
    while kill -0 $restore_pid 2>/dev/null; do
        # Calculate elapsed time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Format elapsed time as minutes:seconds
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        
        # Check log file for progress indicators (optional)
        if [ -f "$log_file" ]; then
            # Count lines in log file as a rough progress indicator
            local log_lines=$(wc -l < "$log_file")
            printf "\r%02d:%02d - %d\r" "$minutes" "$seconds" "$log_lines"
        else
            printf "\r%02d:%02d" "$minutes" "$seconds"
        fi
        sleep 0.3
    done
    printf "\r%02d:%02d - %d\r" "$minutes" "$seconds" "$log_lines"

    # Check the exit status of the restoration process
    wait $restore_pid
    local restore_status=$?
    echo 
    # set -e
    
    if [ $restore_status -eq 0 ]; then
        echo "Restoration completed. Log: $log_file"
        return 0
    else
        echo "Error occurred. Details: $log_file"
        return 1
    fi
}

press_any_key() {
    echo -n "Press any key to continue..."
    read -n 1 -s -r
    echo
}


# ------------------
# MAIN LOGIC
# ------------------

COMPOSE_CMD=$(detect_compose_cmd)
COMPOSE_FILE=$(find_compose_file) || { echo "Error: Docker Compose file not found"; exit 1; }

if [ -f "$BACKUP_DIR/$SQL_TEST_IN_TEST_DB_FILENAME" ]; then
    rm "$BACKUP_DIR/$SQL_TEST_IN_TEST_DB_FILENAME"
fi
if [ -f "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME" ]; then
    rm "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"
fi
if [ -f "$BACKUP_DIR/$SQL_TEST_IN_NEW_DB_FILENAME" ]; then
    rm "$BACKUP_DIR/$SQL_TEST_IN_NEW_DB_FILENAME"
fi

# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
    exit 1
}

DB_SERVICE_NAME=$(get_data_services $COMPOSE_FILE)
echo
echo "--------------------------------"
echo "DB_SERVICE_NAME: $DB_SERVICE_NAME"
echo "--------------------------------"

# Parameter validation
if [ $# -eq 0 ]; then
    show_help
    exit 0
elif [ $# -eq 1 ]; then
    # Container name searching (only the first db service)
    CONTAINER_NAME=$(find_docker_container "$DB_SERVICE_NAME" | xargs) || exit $?
    echo
    echo "--------------------------------"
    echo "Found container: $CONTAINER_NAME"
    echo "--------------------------------"
elif [ $# -eq 2 ]; then
    CONTAINER_NAME="$2"
else
    echo "Error: Too many parameters"
    show_help
    exit 1
fi

case $1 in
    testupgrade)  
        check_container_storage
        if ! confirm_action "Are you sure you want to continue?"; then
            exit 1
        fi

        sql_full_dump $SQL_DUMP_FILE $VERSION_FILE

        # Start test container and check if a container named "pg-test" already exists
        echo
        echo "--------------------------"
        echo "Starting test container..."
        echo "--------------------------"
        if docker ps --format '{{.Names}}' | grep -qw "pg-test"; then
            echo "Container 'pg-test' already exists. Skipping startup."
        else
            if docker ps -a --format '{{.Names}}' | grep -qw "pg-test"; then
                echo "Container 'pg-test' exists but is not running. Removing it..."
                docker rm -f pg-test >/dev/null
            fi

            if confirm_action "Are you sure you want to start the test container? This will download the latest PostgreSQL image if it's not available locally."; then
                echo "Starting test container..."
                docker run --name pg-test \
                    -d $DB_IMAGE || {
                        echo "Error: Failed to start test container" >&2
                        exit 1
                    }
            else
                echo "Test container startup cancelled."
                exit 1
            fi

            # Wait for test container to be ready
            wait_for_postgres $CONTAINER_NAME $DB_USER "postgres" 10 3
        fi

        # Restore dump
        echo
        echo "-----------------------------------------------"
        echo "Restoring dump file to the pg-test container..."
        echo "-----------------------------------------------"
        LOG_FILE="$BACKUP_DIR/db_restore_${DATE}.log"
        # if confirm_action "Are you sure you want to RESTORE the DATABASE? (cat $SQL_DUMP_FILE | $COMPOSE_CMD exec -T $DB_SERVICE_NAME psql -U $DB_USER postgres)"; then
        restore_database_with_progress "$BACKUP_DIR/$SQL_DUMP_FILE" docker pg-test "$DB_USER" "$LOG_FILE"
        # fi

        # docker cp "${BACKUP_DIR}/$SQL_DUMP_FILE" pg-test:/tmp/dump.sql
        # set +e
        # restore_output=$(docker exec pg-test psql -U $DB_USER -d postgres -f /tmp/dump.sql 2>&1)
        # exit_code=$?
        # set -e

        # if [ $exit_code -ne 0 ]; then
        #     echo "Error: Failed to restore dump" >&2
        #     echo "PostgreSQL returned the following error:" >&2
        #     echo "$restore_output" >&2
        #     echo
        #     echo "-----------------------------"
        #     echo "Removing pg-test container..."
        #     echo "-----------------------------"
        #     docker rm -f pg-test >/dev/null
        #     exit 1
        # fi

        # Run test queries and save output
        echo
        echo "-----------------------------"
        echo "Running validation queries..."
        echo "-----------------------------"
        run_test_script $CONTAINER_NAME "$DB_USER" "biomaps" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"
        # Run same queries on production
        run_test_script "pg-test" "$DB_USER" "biomaps" "$BACKUP_DIR/$SQL_TEST_IN_TEST_DB_FILENAME"

        # Compare outputs
        if diff -q "$BACKUP_DIR/$SQL_TEST_IN_TEST_DB_FILENAME" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"; then
            echo
            echo "------------------------------------------------------------"
            echo "Validation successful: Test and production SQL outputs match"
            echo "------------------------------------------------------------"
        else
            echo
            echo "---------------------------------------"
            echo "Validation failed: Differences detected"
            echo "---------------------------------------"
            diff --side-by-side "$BACKUP_DIR/$SQL_TEST_IN_TEST_DB_FILENAME" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"
            exit 1
        fi

        echo
        press_any_key

        # Cleanup
        #docker rm -f pg-test >/dev/null

        echo ""
        echo ""
        echo "----- Additional Manual Test Recommendations -----"
        echo ""
        echo "1. Manual psql Connection Test:"
        echo "   • Connect manually to the test container by running:"
        echo "     docker exec -it pg-test psql -U $DB_USER -d gisdata"
        echo "   • Run a simple command (e.g., 'SELECT version();') to verify that the connection is established."
        echo ""
        echo "2. Database Exploration:"
        echo "   • Switch to the target database using '\\c biomaps' in psql."
        echo "   • List all available tables with '\\dt' to ensure they are accessible."
        echo ""
        echo "3. Structural Validation:"
        echo "   • Verify that all schemas, indexes, and constraints have been restored correctly."
        echo "   • Use commands like '\\d+ <table_name>' in psql or query 'information_schema.table_constraints' to inspect the structure."
        echo ""
        echo "4. User and Role Verification:"
        echo "   • Ensure that required roles (e.g., 'biomapsadmin', 'postgres') exist and have the correct permissions."
        echo "   • You can list roles by running '\\du' in psql or querying the 'pg_roles' table."
        echo ""
        echo "5. Data Integrity Check:"
        echo "   • Run queries such as 'SELECT COUNT(*) FROM <important_table>' on both the production and restored databases."
        echo ""
        echo "6. Read/Write Operations:"
        echo "   • Create a temporary table, insert sample data, and read it back to ensure that the database handles I/O correctly."
        echo ""
        echo "7. Check Docker Container Logs:"
        echo "   • Execute 'docker logs pg-test' to review any warnings or errors during the container startup."
        echo ""
        echo "8. Test Container Restart:"
        echo "   • Stop and then restart the 'pg-test' container."
        echo "   • Check connectivity and data consistency after reboot to verify that the restored database remains stable."
        echo ""
        echo "----- Cleanup Recommendation -----"
        echo ""
        echo "If you have completed testing, you can remove the 'pg-test' container to free up resources."
        echo "Run the following command to delete the test container:"
        echo ""
        echo "    docker rm -f pg-test"
        echo ""
        echo "This will forcefully remove the 'pg-test' container."
        echo ""
        ;;
    upgrade)

        check_container_storage

        if ! confirm_action "Are you sure you want to continue and STOP the CONNECTIONS?"; then
            exit 1
        fi
        stop_connections

        # Checks services
        required_services=("app" "$DB_SERVICE_NAME")
        for service in "${required_services[@]}"; do
            if ! service_exists "$service"; then
                echo "Error: Service '$service' not found in $COMPOSE_FILE"
                exit 1
            fi
        done

        echo
        # Stop Apache
        if ! $COMPOSE_CMD -f "$COMPOSE_FILE" ps app | grep -q "Up"; then
            echo "Apache is already stopped."
        else
            if ! confirm_action "Are you sure you want to STOP the APACHE?"; then
                exit 1
            fi
            $COMPOSE_CMD -f "$COMPOSE_FILE" stop app
        fi

        sql_full_dump "$SQL_DUMP_FILE" "$VERSION_FILE"

        echo
        echo "Running SQL queries for validation..."
        run_test_script $CONTAINER_NAME "$DB_USER" "biomaps" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"

        db_files_backup

        # Original yaml backup
        echo 
        echo "-------------------------------------------------------------------------------------------"
        echo "Backing up original $COMPOSE_FILE file to $BACKUP_DIR/$(basename "$COMPOSE_FILE")_$DATE"
        cp "$COMPOSE_FILE" "$BACKUP_DIR/$(basename "$COMPOSE_FILE")_$DATE"
        echo "Backup completed successfully."
        echo "-------------------------------------------------------------------------------------------"

        press_any_key

        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        if ! confirm_action "Are you sure you want to STOP ALL CONTAINERS (docker-compose down) and MODIFY $COMPOSE_FILE (or exit)!"; then
            exit 1
        fi
        # $COMPOSE_CMD -f "$COMPOSE_FILE" stop "$DB_SERVICE_NAME"
        $COMPOSE_CMD -f "$COMPOSE_FILE" down

        # # Create new volume
        # echo
        # echo "Creating new volume: $PG_NEW_VOLUME..."
        # if ! docker volume create $PG_NEW_VOLUME; then
        #     echo "Error: Failed to create $PG_NEW_VOLUME volume" >&2
        #     exit 1
        # else
        #     echo "Volume $PG_NEW_VOLUME created successfully."
        # fi

        # Modify volume mappings in both the top-level volumes: section and within the db service's volumes in docker-compose file
        DB_VOLUME_NAME=$(extract_volume_from_compose "$COMPOSE_FILE" "$DB_TARGET_PATH")
        echo ""
        if [[ -z "${DB_VOLUME_NAME}" ]]; then
            echo "---------------------------------------------"
            echo "Could not find any Postgres data volume in ${COMPOSE_FILE}. "
            echo "---------------------------------------------"
            create_volume "$COMPOSE_FILE" "$DB_SERVICE_NAME" "$PG_NEW_VOLUME" "$DB_TARGET_PATH"
        elif [[ "$DB_VOLUME_NAME" == "$PG_NEW_VOLUME" ]]; then
            echo "---------------------------------------------"
            echo "The Postgres data volume is already set to $PG_NEW_VOLUME in ${COMPOSE_FILE}. No changes needed."
            echo "---------------------------------------------"
        else    
            echo "---------------------------------------------"
            echo "Found a Postgres Data volume: ${DB_VOLUME_NAME}"
            echo "---------------------------------------------"
            replace_volume "$COMPOSE_FILE" "$DB_VOLUME_NAME" "$PG_NEW_VOLUME"
        fi

        echo "---------------------------------------------"
        echo "Modifying images in docker-compose file..."
        echo "---------------------------------------------"
        # Replace app image in docker-compose file
        update_image "$COMPOSE_FILE" "openbiomaps/web-app:latest" "$APP_IMAGE"

        # Replace mapserver image in docker-compose file
        update_image "$COMPOSE_FILE" "openbiomaps.*.mapserver" "$MAPSERVER_IMAGE"

        # Replace PostgreSQL database image in docker-compose file
        update_image "$COMPOSE_FILE" "$DB_SERVICE_SEARCH_STRINGS" "$DB_IMAGE"

        press_any_key
        echo
        echo "----------------------------------------------------------------"
        echo "Check if named volumes exist in the docker-compose configuration"
        echo "----------------------------------------------------------------"
        check_volume_exists "$COMPOSE_FILE" "$PG_NEW_VOLUME"
        check_volume_exists "$COMPOSE_FILE" "root-private"
        check_volume_exists "$COMPOSE_FILE" "projects"
        check_volume_exists "$COMPOSE_FILE" "var_lib"
        check_volume_exists "$COMPOSE_FILE" "mapserver_log"
        check_volume_exists "$COMPOSE_FILE" "etc_openbiomaps"

echo 
echo "If any named volume is missing, copy and paste the following into the docker-compose.yml file:
...
services:
  app:
    image: $APP_IMAGE
    volumes:
      - var_lib:/var/lib/openbiomaps
      - root-private:/var/www/html/biomaps/root-site/private
      - etc_openbiomaps:/etc/openbiomaps
      - projects:/var/www/html/biomaps/root-site/projects
      - mapserver_log:/tmp/mapserver
...      
  mapserver:
    image: $MAPSERVER_IMAGE
    volumes:
      - mapserver_log:/tmp/mapserver
      - var_lib:/var/lib/openbiomaps
      - projects:/var/www/html/biomaps/root-site/projects
...
  biomaps_db:
    image: $DB_IMAGE
    volumes:
      - $PG_NEW_VOLUME:/var/lib/postgresql/data
...
volumes:
  $PG_NEW_VOLUME:
  root-private:
  projects:
  var_lib:
  mapserver_log:
  etc_openbiomaps:"


        echo
        if confirm_action "Would you like to REVIEW $COMPOSE_FILE and PASTE missing named volumes?"; then
            $(get_available_editor) "$COMPOSE_FILE"
        fi

        echo
        if confirm_action "Are you sure, you want to START all CONTAINERS except 'app', and proceed with the RESTORE process OR EXIT? ($COMPOSE_CMD -f "$COMPOSE_FILE" up -d)"; then
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d
            $COMPOSE_CMD stop app
        else 
            exit 1
        fi

        echo
        echo "--------------------------------------------------------"
        echo "Restoring dump file to the $DB_SERVICE_NAME container..."
        echo "--------------------------------------------------------"
        # Database restore
        LOG_FILE="$BACKUP_DIR/db_restore_${DATE}.log"
        if confirm_action "Are you sure you want to RESTORE the DATABASE? (cat $BACKUP_DIR/$SQL_DUMP_FILE | $COMPOSE_CMD exec -T $DB_SERVICE_NAME psql -U $DB_USER postgres)"; then
            restore_database_with_progress "$BACKUP_DIR/$SQL_DUMP_FILE" "$COMPOSE_CMD" "$DB_SERVICE_NAME" "$DB_USER" "$LOG_FILE"
        else
            exit 1
        fi

        # Run test queries and save output
        echo
        echo "-----------------------------"
        echo "Running validation queries..."
        echo "-----------------------------"
        # Run same queries on production
        run_test_script "$CONTAINER_NAME" "$DB_USER" "biomaps" "$BACKUP_DIR/$SQL_TEST_IN_NEW_DB_FILENAME"

        $COMPOSE_CMD start app

        # Compare outputs
        if diff -q "$BACKUP_DIR/$SQL_TEST_IN_NEW_DB_FILENAME" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"; then
            echo
            echo "---------------------------------------------------------------------------------"
            echo "Validation successful: the new upgraded and previous production SQL outputs match"
            echo "---------------------------------------------------------------------------------"
        else
            echo
            echo "---------------------------------------"
            echo "Validation failed: Differences detected"
            echo "---------------------------------------"
            diff --side-by-side "$BACKUP_DIR/$SQL_TEST_IN_NEW_DB_FILENAME" "$BACKUP_DIR/$SQL_TEST_IN_PROD_DB_FILENAME"
        fi

        echo "Setting up biomapsadmin, sablon_admin and mainpage_admin password (./obm_post_install.sh update sql)..."
        ./obm_post_install.sh update sql

        ;;

    *)
        echo "Error: Unknown command" >&2
        show_help
        exit 1
        ;;
esac

