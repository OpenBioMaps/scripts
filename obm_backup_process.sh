i=$1

alldata="non-synced"

if [ $# -eq 0 ]
  then
    echo "No backup file supplied"
    exit
fi

if [ $# -eq 2 ] && [ "$2" == "all" ]
then
    echo "Processing all data"
    alldata="all"
fi

if [ $# -eq 2 ] && [ "$2" == "synced" ]
then
    echo "Processing only synced data"
    alldata="synced"
fi

#a=$i.json
# Create JSON from backup
#sed 's/\\//g' $i | sed 's/:"{/:{/g' | sed 's/}"/}/g' | sed 's/:"\[/:[/g' | sed 's/\]",/],/g' | sed 's/"count":{\([0-9]*\),\([0-9]*\)}/"count":[\1,\2]/g' | sed 's/"count":{\([0-9]*\)}/"count":[\1]/g' | jq > $a

# ezt php-ban sikerült jól megoldani....
php ./obm_backup_process.php $i

a=$i.json

# List of servers:
servers=`jq '.servers.data[] | select(.id!="").id' $a | tr -d '"'`

PS3="Choose a server: "
select url in $servers
do
    echo "${url}"
    break
done
#url=$2 # http://milvus.openbiomaps.org

#name=$3 # OpenBirdMaps 
projects=`jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | .name' $a`
PS3="Choose a project: "
eval set $projects
select name in "$@"
do
    echo "${name}"
    break
done

#jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data | map(has("measurements"))' $a

# forms width data
e="jq '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data | map(has(\"measurements\"))' $a"

forms=`echo $e | bash |  grep -n true | awk -F : '{print $1-2}'`

for f in $forms
do
    e="jq '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].id' $a | tr -d '\"'"
    formId=`echo $e | bash`

    if [ "$alldata" = "non-synced" ]
    then
        e="jq '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | select(.isSynced==false) | length' $a | wc -l"
        records=`echo $e | bash`
        echo "$records non-synced records found in form $formId"
        e="jq -r '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | select(.isSynced==false) | @json' $a > $formId"_data.json
        echo $e | bash
    elif [ "$alldata" = "synced" ]
    then
        e="jq '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | select(.isSynced==true) | length' $a | wc -l"
        records=`echo $e | bash`
        echo "$records synced records found in form $formId"
        e="jq -r '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | select(.isSynced==true) | @json' $a > $formId"_data.json
        echo $e | bash
    else
        e="jq '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | length' $a | wc -l"
        records=`echo $e | bash`
        echo "$records records found in form $formId"
        e="jq -r '.servers.data[] | select(.id==\"$url\") | .databases.data[] | select(.name==\"$name\") | .observations.data['$f'].measurements.data[] | @json' $a > $formId"_data.json
        echo $e | bash
    fi

    php ./obm_backup_process.php $formId "$formId"_data.json
    
    #header=`jq -r '.data | del(.obm_geometry) |  del(.obm_files_id) | keys_unsorted | . +=["longitude","latitude"]| @csv' $formId"_data.json"`
    #jq -r '.data |del(.obm_geometry) |  del(.obm_files_id) | keys_unsorted | . +=["longitude","latitude"]| @csv' $formId"_data.json" 2> header.csv
    #jq -r '.data |= . + {longitude:.obm_geometry.longitude,latitude:.obm_geometry.latitude} | .data | del(.obm_geometry) |  del(.obm_files_id) | [.[]] | @csv' $formId"_data.json" > data.csv

    #n=1
    #while IFS= read -r line
    #do
    #    echo -e "$line\n" $(head -n $n data.csv | tail -n 1) >> $formId"_output.csv"
    #   n=$((n+1))
    #done < <(printf '%s\n' "$header")

    #echo -e "$head\n$data" > $formId"_output.csv"

    #minden adat
    #jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data['$f'].measurements.data' $a > $formId"_data.json"
done


#jq -r '[.data] | map({dt_from,gyujto,magyar,egyedszam,location}) | (first | keys_unsorted) as $keys | map([to_entries[] | .value]) as $rows | $keys,$rows[] | @csv' 191_data.json
#jq '[.data] | map([to_entries[] | .value]) | del(.[] | .[] | select(type=="object")) ' 191_data.json

# data keys
#jq -r '.data | keys | @csv' 191_data.json

# data keys without obm_geometry
#jq -r '.data |del(.obm_geometry) | keys| @csv' 191_data.json


# data keys without obm_geometry and added longitude, latitude

# values without obm_geometry in csv format
#jq -r '.data| del(.obm_geometry) | [.[]] | @csv' 191_data.json

# longitude, latitude
#jq -r '.data.obm_geometry| [.[]] | @csv' 191_data.json


# extract a specific form data:
#jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data[] | select(.id=="157") | .measurements.data | keys' $a
#get_form=565
#jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data[] | select(.id=="'$get_form'") | .measurements.data' $a > $get_form"_data.json"
