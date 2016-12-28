#!/bin/bash

#OpenBioMaps archive script by Miki Bán banm@vocs.unideb.hu
#2016-10-31
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
doweek=`date +"%d"`
month=`date +"%m"`
day=`date +"%u"`
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
special_tables=(uploadings files file_connect)
#tables=( $(cat $table_list) )
dbs=(gisdata biomaps)
archive_path="/home/archives"
tables=()

# Remote 
remote_user=''
remote_site=''
remote_path=''

case "$1" in
normal) echo "dumping tables"

    while read i
    do
        [[ $i == "#"* ]] && continue
        IFS=' ' read -r -a sa <<< "$i"
        crd=${sa[1]} #day
        crw=${sa[2]} #week
        crm=${sa[3]} #month
        table=${sa[0]}
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
                            # automatically add history and taxon tables
                            # probably some customization would be nice
                            tables+=( `printf "%s_history %s_taxon" $table $table` )
                        fi
                    else
                        tables+=( $table )
                    fi
                fi
            fi
        fi
    done < $table_list

    #run
    for k in "${tables[@]}"
    do 
        printf "pg_dump -U gisadmin -f %s/gisdata_%s_%s.sql -n public -t %s gisdata" $archive_path $k $date $k | bash
        #printf "pg_dump -U gisadmin -f %s/gisdata_%s_%s.sql -n public -t %s gisdata\n" $archive_path $k $date $k
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
        printf "pg_dump -U gisadmin -f %s/%s_%s.sql -n public %s" $archive_path $i $date $i | bash
    done

echo "."
;;
sync) echo "syncing to remote hosts"
    
    pattern="$2"
    if [ "$pattern" = '' ]; then
        # simple copy
        rsync -ave ssh $archive_path/ $remote_user@$remote_site:$remote_path/
    else
        # complex pattern based copy
        find $archive_path -name "$pattern" -print0 | tar --null --files-from=/dev/stdin -cf - | ssh $remote_user@$remote_site tar -xf - -C $remote_path
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
    printf "find %s -type f -name '*.gz' -mtime +$n2 -print -exec rm {} \;" $archive_path | bash

echo "."
;;

esac
exit 0
