#!/bin/bash

# OpenBioMaps archive script by Miklós Bán <banm@vocs.unideb.hu>
# 2016-10-31, 12.28, 2018.03.02, 2018.09.29, 2024-08-16, 2025-01-16
# feel free to upgrade it!
# please share your improvements:
# administrator@openbiomaps.org

# crontab usage examples:
# only tables from Monday to Saturday
#15 04 * * 1-6 /home/banm/archive.sh normal &
# tables and whole databases on every Sunday
#15 04 * * 7 /home/banm/archive.sh full &

# Example settings in 
#table dayof_week dayofmonth month
#foo at every day
#foo * * *
#bar every Monday
#bar 1 * *
#casbla at every 1st day of every June
#casbla * 1 6

# Variables - set them as you need
date=`date +"%b-%d-%y_%H:%M"`
settings_path='' # e.g. _dinpi

# cron like archive sttings
doweek=`date +"%-d"`
month=`date +"%-m"`
day=`date +"%-u"`

# tables in the gisdata.system
special_tables=(evaluations file_connect files imports polygon_users query_buff shared_polygons uploadings tracklogs)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source $DIR/obm_archive_settings$settings_path.sh

#tables=( $(cat $table_list) )
dbs=($all_project_databases)
tables=()
d=()
schema=()

case "$1" in
normal) echo "dumping tables"

    while read i
    do
        [[ $i == "#"* ]] && continue
        IFS=' ' read -r -a sa <<< "$i"
        crd=${sa[1]} #day
        crw=${sa[2]} #week
        crm=${sa[3]} #month
        i_table=${sa[0]}
        a_table=(${i_table//./ })
        database=$project_database
        if [[ ${#a_table[@]} -eq 2 ]];then
            database=${a_table[0]}
            table=${a_table[1]}
        else
            table=${a_table[0]}
        fi

        #crony
        if [[ "$crm" == "*" || "$crm" == "$month" ]]; then
            if [[ "$crw" == "*" || "$crw" == "$doweek" ]]; then
                if [[ "$crd" == "*" || "$crd" == "$day" ]]; then
                    if ! echo ${special_tables[@]} | grep -q -w "$table"; then 
                        # normal tables
                        mt=$(echo "SELECT f_project_table as t FROM projects LEFT JOIN header_names ON (f_project_name=project_table) WHERE project_table='$table'" | $psql -t -h localhost -U $admin_user $system_database)
                        if [ -z "$mt" ]; then
                            echo "Unknown project: $table"
                        else
                            main_tables=(${mt//;/ })
                            tables+=( "${main_tables[@]}" )
                            for mk in "${main_tables[@]}"
                            do
                                d+=( "$database" )
                                schema+=( "public" )
                            done
                            # automatically add history and taxon tables
                            # probably some customization would be nice
                            schema+=( "public" "public" )
                            tables+=( `printf "%s_history %s_taxon" $table $table` )
                            d+=( `printf "%s %s" $database $database` )
                        fi
                    else
                        # special tables
                        schema+=( "system" )
                        tables+=( "$table" )
                        d+=( "$database" )
                    fi
                fi
            fi
        fi
    done < $table_list

    #run
    c=0
    for table in "${tables[@]}"
    do 
        printf "%s -h localhost -U %s -t ${schema[$c]}.%s %s | gzip > %s/%s_%s_%s.sql.gz\n" "$pg_dump" $admin_user $table ${d[$c]} $archive_path ${d[$c]} $table $date | bash
        c=$((c+1))
    done

echo "."
;;
full) echo "dumping databases"
    
    for db in "${dbs[@]}"
    do 
        if [ $# -eq 2 ] && [ $db != $2 ]; then 
            continue
        fi
        echo $db
        # extension is bzip2 to prevent auto cleaning and auto sync
        #printf "%s -h localhost -U %s -n public %s | bzip2 > %s/%s_%s.sql.bzip2" "$pg_dump" $admin_user $db $archive_path $db $date | bash
        printf "%s -h localhost -U %s %s | bzip2 > %s/%s_fulldbarchive_%s.sql.bzip2" "$pg_dump" $admin_user $db $archive_path $db $date | bash
    done

echo "."
;;
system) echo "dumping system database"
    
    #printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s\n" $archive_path $system_database $date $system_database
    #printf "%s -h localhost -U %s -n public %s | gzip > %s/%s_%s.sql.gz" "$pg_dump" $admin_user $system_database $archive_path $system_database $date | bash
    printf "%s -h localhost -U %s %s | gzip > %s/%s_%s.sql.gz" "$pg_dump" $admin_user $system_database $archive_path $system_database $date | bash

echo "."
;;
projects) echo "dumping project database"
    
    #printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s\n" $archive_path $project_database $date $project_database
    #printf "%s -h localhost -U %s -n public %s | gzip > %s/%s_%s.sql.gz" "$pg_dump" $admin_user $project_database $archive_path $project_database $date | bash
    printf "%s -h localhost -U %s %s | gzip > %s/%s_%s.sql.gz" "$pg_dump" $admin_user $project_database $archive_path $project_database $date | bash

echo "."
;;
sync) echo "syncing to remote hosts"

    # example
    #obm_archive.sh sync banm@dinpi.openbiomaps.org /home/archives/openbiomaps.org_archive
    
    # Remote 
    remote_ssh=$2
    remote_path=$3
    pattern="$4"

    if [ "$pattern" == '' ]; then
        # copy all files which newer than 3 days
        cd $archive_path
        rsync -Ravh --files-from=<(find ./ -mtime -3 -type f) . $remote_ssh:$remote_path
    else
        # copy pattern match files
        find $archive_path/ -name '$pattern' -type f -mtime -3 -print0 | tar --null --files-from=/dev/stdin -cf - | ssh $remote_ssh tar -xf - -C $remote_path/
    fi

echo "."
;;
curl-sync) echo "syncing to remote hosts using curl"

    # example
    #obm_archive.sh sync banm@dinpi.openbiomaps.org /home/archives/openbiomaps.org_archive
    
    # Remote 
    remote_user=$2
    remote_path=$3

    # copy all files which newer than 3 days
    cd $archive_path
    find ./ -mtime -3 -type f | while read fname; do
        bname=`basename "$fname"`
        curl -X PUT -u $remote_user "$remote_path/$bname" --data-binary @"$fname"
    done    

echo "."
;;
clean) echo "cleaning: gzipping sql files and deleting old gzip files"
    
    # run it every day
    keep_days=15
    if [ ! -z "$2" ]; then
        keep_days="$2"
    fi
    # gzipping non-gzipped sql files
    printf "find %s -type f -name '*.sql' -print -exec gzip {} \;" $archive_path | bash
    # delete every gzip file older than keep_days
    printf "find %s -type f -name '*.sql.gz' -mtime +$keep_days -print -exec rm {} \;" $archive_path | bash
    # delete old full archives
    printf "find %s -type f -name '*.sql.bzip2' -mtime +365 -print -exec rm {} \;" $archive_path | bash

    # clean logs
    echo "DELETE FROM oauth_access_tokens WHERE expires < now();" | $psql -t -h localhost -U $admin_user $system_database
    echo "DELETE FROM oauth_refresh_tokens WHERE expires < now();" | $psql -t -h localhost -U $admin_user $system_database

echo "."
;;

esac
exit 0
