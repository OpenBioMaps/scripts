#!/bin/bash

# This is a script for cleaning archive directories

if [ -z "$1" ]; then
    echo "Error: TARGET_PATTERN argumentum is missing! E.g. dinpi_data"
    exit 1
fi

# Target direcotry is the folder where the cleaning should happen
TARGET_DIR="/home/archives/openbiomaps.org_archive"
TARGET_PATTERN=$1

# Delete files in each projects
cleanup_category() {
    local category="$1"
    local min_keep="$2"

    #echo "Kategória tisztítása: $category, megtartandó fájlok száma: $min_keep"

    local regex="^.*/${category}_[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]-[0-9][0-9].*"

    # Search for files match with criterias
    find "$TARGET_DIR" -type f -regex "$regex" \
        | sort -r \
        | tail -n +$((min_keep + 1)) \
        | while read -r file; do
            #echo "Delete: $file"
            rm -f "$file"
        done
}

# Query all categories
categories=$(find "$TARGET_DIR" -type f -name "$TARGET_PATTERN*" \
    | sed -E 's|.*/('$TARGET_PATTERN'(.+)?)_[A-Za-z]{3}-[0-9]{2}-[0-9]{2}(_[0-9]{2}:[0-9]{2})?\.sql\.(gz\|bzip2)$|\1|' \
    | sort | uniq)

# Processing categories
for category in $categories; do
    if [[ "$category" =~ "fulldbarchive" ]]; then
        # In fulldbarchive only keep 2 files
        cleanup_category "${category}" 2
    else
        # Keep 14 files in all other categories
        cleanup_category "${category}" 14
    fi
done

