#!/bin/bash

#OpenBioMaps archive script by Miki Bán banm@vocs.unideb.hu
#2016-10-31, 12.28
#feel free to upgrade it!
#please share your improvements:
#administrator@openbiomaps.org

# crontab usage examples:
# only tables from Monday to Saturday
#15 04 * * 1-6 /home/banm/archive.sh normal &
# tables and whole databases on every Sunday
#15 04 * * 7 /home/banm/archive.sh full &

# Variables - set them as you need
date=`date +"%b-%d-%y_%H:%M"`
# cron like archive sttings
doweek=`date +"%-d"`
month=`date +"%-m"`
day=`date +"%-u"`
# path of table list
table_list="${HOME}/.archive_list.txt"
#table dayof_week dayofmonth month
#foo at every day
#foo * * *
#bar every Monday
#bar 1 * *
#casbla at every 1st day of every June
#casbla * 1 6


# tables in gisdata
project_database="gisdata"
system_database="biomaps"
special_tables=(uploadings files file_connect evaluations imports polygon_users shared_polygons query_buff)
#tables=( $(cat $table_list) )
dbs=($project_database $system_database)
archive_path="/home/archives"
pg_dump="pg_dump -p 5432"
tables=()
d=()

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
                        mt=$(echo "SELECT array_to_string(main_table,';') as t FROM projects WHERE project_table='$table'" | psql -t -h localhost -U gisadmin biomaps)
                        if [ -z "$mt" ]; then
                            echo "Unknown project: $table"
                        else
                            main_tables=(${mt//;/ })
                            tables+=( "${main_tables[@]}" )
                            for mk in "${main_tables[@]}"
                            do
                                d+=( "$database" )
                            done
                            # automatically add history and taxon tables
                            # probably some customization would be nice
                            tables+=( `printf "%s_history %s_taxon" $table $table` )
                            d+=( `printf "%s %s" $database $database` )
                        fi
                    else
                        # special tables
                        tables+=( "$table" )
                        d+=( "$database" )
                    fi
                fi
            fi
        fi
    done < $table_list

    #run
    c=0
    for k in "${tables[@]}"
    do 
        #printf "pg_dump -U gisadmin -f %s/%s_%s_%s.sql -n public -t %s %s\n" $archive_path ${d[$c]} $k $date $k ${d[$c]}
        printf "%s -U gisadmin -f %s/%s_%s_%s.sql -n public -t %s %s" "$pg_dump" $archive_path ${d[$c]} $k $date $k ${d[$c]} | bash
        c=$((c+1))
    done

echo "."
;;
full) echo "dumping databases"
    
    for i in "${dbs[@]}"
    do 
        if [ $# -eq 2 ] && [ $i != $2 ]; then 
            continue
        fi
        echo $i
        #printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s\n" $archive_path $i $date $i
        printf "%s -U gisadmin -f %s/%s_%s.sql -n public %s" "$pg_dump" $archive_path $i $date $i | bash
    done

echo "."
;;
system) echo "dumping system database"
    
    #printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s\n" $archive_path $system_database $date $system_database
    printf "%s -U gisadmin -f %s/%s_%s.sql -n public %s" "$pg_dump" $archive_path $system_database $date $system_database | bash

echo "."
;;
projects) echo "dumping project database"
    
    #printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s\n" $archive_path $project_database $date $project_database
    printf "%s -U gisadmin -f %s/%s_%s.sql -n public %s" "$pg_dump" $archive_path $project_database $date $project_database | bash

echo "."
;;
sync) echo "syncing to remote hosts"
    
    # Remote 
    remote_ssh=$2
    remote_path=$3
    pattern="$4"

    if [ "$pattern" = '' ]; then
        # simple copy
        rsync -ave ssh $archive_path/ $remote_ssh:$remote_path/
    else
        # complex pattern based copy
        find $archive_path -name "$pattern" -print0 | tar --null --files-from=/dev/stdin -cf - | ssh $remote_ssh tar -xf - -C $remote_path
    fi

echo "."
;;
clean) echo "cleaning: gzipping sql files and deleting old gzip files"
    
    # run it every month
    n1=7
    n2=30
    if [[ ! -z "$2" && -z "$3" ]]; then
        n1="$2"
    elif [ ! -z "$3" ]; then
        n1="$2"
        n2="$3"
    fi
    # gzipping everything older than 7 days
    printf "find %s -type f -name '*.sql' -mtime +$n1 -print -exec gzip {} \;" $archive_path | bash
    # delete every gzip file older than 30 days
    # how can I keep 1/month?
    printf "find %s -type f -name '*.sql.gz' -mtime +$n2 -print -exec rm {} \;" $archive_path | bash

echo "."
;;

esac
exit 0
