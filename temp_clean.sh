#!/bin/bash

DB=$1

while true; do
  deleted=$(psql -U biomaps_admin -h localhost -At -d $DB -c "
    DELETE FROM system.temp_index
    WHERE table_name IN (
      SELECT table_name
      FROM system.temp_index ti
      LEFT JOIN system.imports i ON ti.table_name = i.file
      WHERE i.project_table IS NULL
        AND ti.datum < NOW() - INTERVAL '1 day'
      LIMIT 500
    )
    RETURNING 1;" | wc -l)

  echo "Törölve: $deleted sor"
  [ "$deleted" -le 1 ] && break

  sleep 0.1
done

