# path of table list
table_list="${HOME}/.archive_list.txt"

# postgres parameters
project_database="gisdata"
system_database="biomaps"
all_project_databases="gisdata"
admin_user="gisadmin"
archive_path="/home/archives"
pgport="5432"
pg_dump="pg_dump -p $pgport"
psql="psql -p $pgport"

# FOR DOCKER based OBM systems
# docker="/usr/bin/docker-compose -f /PATH/TO/docker-compose.yml exec -T"
# pg_dump="$docker biomaps_db pg_dump -p $pgport"
# psql="$docker biomaps_db psql -p $pgport"

