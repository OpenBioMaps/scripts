## OpenBioMaps install script
##

mkdir /etc/openbiomaps
mkdir -p /var/lib/openbiomaps/tmp/
mkdir -p /var/lib/openbiomaps/maps/
mkdir -p /var/www/html/biomaps/
mkdir -p /var/www/html/biomaps/projects/sablon
mkdir -p /var/www/html/biomaps/css
mkdir -p /var/www/html/biomaps/js
mkdir -p /var/www/html/biomaps/languages
mkdir -p /var/www/html/biomaps/libs
mkdir -p /var/www/html/biomaps/oauth
mkdir -p /var/www/html/biomaps/templates
mkdir -p /var/www/html/biomaps/uploads
mkdir -p /var/www/html/biomaps/Images

cp etc/openbiomaps/system_vars.php.inc /etc/openbiomaps/
cp usr/lib/cgi-bin/.htaccess /usr/lib/cgi-bin/
cat sr/share/proj/google.epsg >> /sr/share/proj/epsg
cp -r var/lib/openbiomaps/maps/ /var/lib/openbiomaps/maps/
cp -r sablon/ /var/www/html/biomaps/projects/sablon/
cp -r var/www/html/biomaps/oauth/ /var/www/html/biomaps/oauth/
cp -r var/www/html/biomaps/pds/ /var/www/html/biomaps/pds/
cp -r var/www/html/biomaps/Images/ /var/www/html/biomaps/Images/
cp -r var/www/html/biomaps/languages/ /var/www/html/biomaps/languages/
cp var/www/html/biomaps/*.php /var/www/html/biomaps/
cp var/www/html/biomaps/*.html /var/www/html/biomaps/
cp var/www/html/biomaps/.htaccess /var/www/html/biomaps/
cp var/www/html/biomaps/local_vars.php.inc /var/www/html/biomaps/
cp var/www/html/biomaps/*.txt /var/www/html/biomaps/

psql < db_structure/biomaps_roles.sql
psql < db_structure/biomaps_structure.sql
psql < db_structure/biomaps_data.sql
psql < db_structure/gisdata_structure.sql
