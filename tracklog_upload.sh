#!/bin/bash

schema=public
table=hunviphab
user_id=22
seq=`printf "%s_tracklogs_id_seq" $table`

for f in `ls *.gpx`
do
    echo "Processing $f"

    name=$(echo "$f" | cut -f 1 -d '.')

    ogr2ogr -f GeoJSON $f.json $f track_points

    #INSERT INTO "public"."hunviphab_tracklogs" ("id","user_id","start_time","end_time","tracklog_geom","trackname","tracklog_id","tracklog_line_geom")
    #					VALUES (nextval('hunviphab_tracklogs_id_seq'::regclass),'22','0','1','{}','adsasd',NULL,'')

    start_time=`jq '.features[0].properties.time' $f.json | tr -d '"'`
    end_time=`jq '.features[-1].properties.time' $f.json | tr -d '"'`
    
    a=`printf "INSERT INTO \"%s\".\"%s_tracklogs\" (id,user_id,start_time,end_time,tracklog_geom,trackname,tracklog_id,tracklog_line_geom) " $schema $table`

    b=$(echo "VALUES ( nextval('$seq'::regclass),'$user_id','$start_time','$end_time','$(cat $f.json)','$name',NULL,NULL )")

    echo -e "$a\n$b" > $name.sql

done

# psql -h knp.openbiomaps.org -d __gisdata__ -U __admin___ < ....sql

