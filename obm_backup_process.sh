i=$1
#a=$i.json
# Create JSON from backup
#sed 's/\\//g' $i | sed 's/:"{/:{/g' | sed 's/}"/}/g' | sed 's/:"\[/:[/g' | sed 's/\]",/],/g' | sed 's/"count":{\([0-9]*\),\([0-9]*\)}/"count":[\1,\2]/g' | sed 's/"count":{\([0-9]*\)}/"count":[\1]/g' | jq > $a

# ezt php-ban sikerült jól megoldani....
php ./obm_backup_process.php $i

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
forms=`jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data | map(has("measurements"))' $a | grep -n true | awk -F : '{print $1-2}'`

for f in $forms
do
    formId=`jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data['$f'].id' $a | tr -d '"'`
    records=`jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data['$f'].measurements.data[] | select(.isSynced==false) | length' $a | wc -l`
    #select(.isSynced=="false")
    echo "$records non-synced records found in form $formId"
    jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data['$f'].measurements.data[] | select(.isSynced==false)' $a > $formId"_data.json"

    #minden adat
    #jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data['$f'].measurements.data' $a > $formId"_data.json"
done


# extract a specific form data:
#jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data[] | select(.id=="157") | .measurements.data | keys' $a
#get_form=565
#jq '.servers.data[] | select(.id=="'$url'") | .databases.data[] | select(.name=="'$name'") | .observations.data[] | select(.id=="'$get_form'") | .measurements.data' $a > $get_form"_data.json"
