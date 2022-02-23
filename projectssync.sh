#!/bin/bash

#rsync -av --include="*/" --include="*.php" --exclude="*" --exclude="*" ./ ../danubefish/

#rsync -ave ssh --exclude="**UMS_REPOSITORY" danubefish/ biomaps.unideb.hu:/var/www/projects/danubefish/

#rsync -ave ssh --include="*/" --include="**.php" --exclude="*" --exclude="**UMS_REPOSITORY" ./ biomaps.unideb.hu:/var/www/projects/dinpi/

bn=`pwd`
bn=`basename $bn`
dryrun=v$1

# local project dir TO other local project dirs
# ...

# local project dir TO remote project dir
echo -e "local project dir TO remote project dir"
printf 'rsync -a%se ssh --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude=".htaccess" ./ biomaps.unideb.hu:/var/www/projects/%s/\n' $dryrun $bn
printf 'rsync -a%se ssh --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude=".htaccess" ./ biomaps.unideb.hu:/var/www/projects/%s/' $dryrun $bn|bash

# local project sync TO local template
echo -e "local project sync TO local template"
printf 'rsync -a%s --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude="*.map" --exclude=".htaccess" ./ ../../template/\n' $dryrun
printf 'rsync -a%s --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude="*.map" --exclude=".htaccess" ./ ../../template/' $dryrun|bash

# local tempalte sync TO remote tempalte
echo -e "local tempalte sync TO remote tempalte"
printf 'rsync -a%se ssh --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude="*.map" --exclude=".htaccess" /home/banm/web/biomaps/template/ biomaps.unideb.hu:/var/www/template/\n' $dryrun
printf 'rsync -a%se ssh --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude="*.map" --exclude=".htaccess" /home/banm/web/biomaps/template/ biomaps.unideb.hu:/var/www/template/' $dryrun|bash


# project to project
#printf 'rsync -a%s --exclude="**UMS_REPOSITORY" --exclude="*.inc" --exclude="*.swp" --exclude="*.swo" --exclude="*.map" --exclude=".*" --exclude="*.png" --exclude="*.jpg" ./ ../%s/' $dryrun $2
