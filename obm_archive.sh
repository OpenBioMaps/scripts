#!/bin/bash

#OpenBioMaps archive script by Miki Bán banm@vocs.unideb.hu
#2016-10-31
#feel free to upgrade it!
#please share your improvements:
#administrator@lists.openbiomaps.org
#https://github.com/OpenBioMaps/archive_scripts

# crontab usage examples:
# only tables from Monday to Saturday
#15 04 * * 1-6 /home/banm/archive.sh normal &
# tables and whole databases on every Sunday
#15 04 * * 7 /home/banm/archive.sh full &

# Variables - set them as you need
date=`date +"%b-%d-%y_%H:%M"`
# tables in gisdata
tables=(templates templates_genetics templates_taxon files file_connect)
dbs=(gisdata biomaps)
archive_path="/home/archives"

# Remote 
remote_user=''
remote_site=''
remote_path=''

case "$1" in
normal) echo "dumping tables"

    for i in "${tables[@]}"
    do 
        printf "pg_dump -U gisadmin -f %s/gisdata_%s_%s.sql -n public -t %s gisdata\n" $archive_path $i $date $i | bash
    done

echo "."
;;
full) echo "dumping tables and databases"
    
    echo "tables"
    for i in "${tables[@]}"
    do 
        printf "pg_dump -U gisadmin -f %s/gisdata_%s_%s.sql -n public -t %s gisdata" $archive_path $i $date $i | bash
    done

    echo "databases"
    for i in "${dbs[@]}"
    do 
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
    printf "find %s -type f -name '*.sql' -mtime +$n1 -print -exec gzip {} \;" $archive_path | bash
    printf "find %s -type f -name '*.gz' -mtime +$n2 -print -exec rm {} \;" $archive_path | bash

echo "."
;;

esac
exit 0
