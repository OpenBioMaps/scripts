#!/bin/bash
# GIT source sync to Production server
# Miki, Bán
# 2017.03.05

server="banm@openbiomaps.org"
server_path="/var/www/html/biomaps"
git_folder="/var/www/html/biomaps"

cd $server_path

folder="libs/languages"
echo $folder
rsync -ave ssh $folder/*.php  $server:$server_path/$folder/

folder="libs"
echo $folder
rsync -ave ssh $folder/*.php  $server:$server_path/$folder/

folder="libs/modules"
echo $folder
rsync -ave ssh $folder/*.php  $server:$server_path/$folder/

folder="libs/js"
echo $folder
rsync -ave ssh $folder/*.js  $server:$server_path/$folder/

folder="libs/css"
echo $folder
rsync -ave ssh $folder/*.css  $server:$server_path/$folder/

folder="pds"
echo $folder
rsync -ave ssh $folder/*.php  $server:$server_path/$folder/

folder="templates/initial/root"
echo $folder
rsync -tve ssh $folder/*.php  $server:$server_path/$folder/
rsync -tve ssh $folder/*.inc  $server:$server_path/$folder/
rsync -ave ssh $folder/.htaccess  $server:$server_path/$folder/

folder="templates/initial/private"
echo $folder
rsync -tve ssh $folder/*.map  $server:$server_path/$folder/

folder="templates/initial/public"
echo $folder
rsync -tve ssh $folder/*.map  $server:$server_path/$folder/

folder="oauth"
echo $folder
rsync -tve ssh $folder/*.php  $server:$server_path/$folder/

# optional - local modules
folder="projects/milvus/modules"
echo $folder
rsync -ave ssh $folder/*.php  $server:$server_path/$folder/

echo "\nDone."
