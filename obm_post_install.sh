#!/bin/bash

#postgres_password=$(cat .env | grep BIOMAPS_POSTGRES_PASSWORD | awk -F : '{print $2}')
biomaps_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32})
mainpage_admin_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32})
sablon_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32})
sablon_hash=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-8})

docker-compose exec -T gisdata bash -c "psql -U gisdata -c \"ALTER ROLE biomapsadmin WITH PASSWORD '$biomaps_password';\""
docker-compose exec -T gisdata bash -c "psql -U gisdata -c \"ALTER ROLE sablon_admin WITH PASSWORD '$sablon_password';\""
docker-compose exec -T biomaps bash -c "psql -U biomaps -c \"ALTER ROLE biomapsadmin WITH PASSWORD '$biomaps_password';\""
docker-compose exec -T biomaps bash -c "psql -U biomaps -c \"ALTER ROLE mainpage_admin WITH PASSWORD '$mainpage_admin_password';\""

# replace this line in econf/system_vars.php.inc
if test $# -eq 0; then
    update=0
else
    update=$1
fi

if [ "$update" = "update" ]; then
    docker-compose exec -T app bash -c "sed -i 's/\(biomapsdb_pass.,.\).*/\1$biomaps_password\x27);/' /etc/openbiomaps/system_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\(mainpage_pass.,.\).*/\1$mainpage_admin_password\x27);/' /etc/openbiomaps/system_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\(gisdb_pass.,.\).*/\1$sablon_password\x27);/' /var/www/html/biomaps/root-site/projects/sablon/local_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\(MyHASH.,.\).*/\1$sablon_hash\x27);/' /var/www/html/biomaps/root-site/projects/sablon/local_vars.php.inc"
else
    docker-compose exec -T app bash -c "sed -i 's/\*\*\* ChangeThisPassword-1 \*\*\*/$biomaps_password/' /etc/openbiomaps/system_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\*\*\* ChangeThisPassword-2 \*\*\*/$mainpage_admin_password/' /etc/openbiomaps/system_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\*\*\* ChangeThisPassword \*\*\*/$sablon_password/' /var/www/html/biomaps/root-site/projects/sablon/local_vars.php.inc"
    docker-compose exec -T app bash -c "sed -i 's/\*\*\* ChangeThisHash \*\*\*/$sablon_hash/' /var/www/html/biomaps/root-site/projects/sablon/local_vars.php.inc"
fi

docker-compose exec -T mapserver bash -c "msencrypt -keygen /var/lib/openbiomaps/maps/access.key"
access_key=$(docker-compose exec -T mapserver bash -c "cat /var/lib/openbiomaps/maps/access.key")
sablon_password_hash=$(docker-compose exec -T mapserver bash -c "msencrypt -key /var/lib/openbiomaps/maps/access.key $sablon_password | tr -d '\n'")
if [ "$update" = "update" ]; then
    docker-compose exec -T app bash -c "sed -i 's/ password={.*} / password={$sablon_password_hash} /' /var/www/html/biomaps/root-site/projects/sablon/private/private.map"
else
    docker-compose exec -T app bash -c "sed -i 's/\*\*\* ChangeThisPasswordHash \*\*\*/$sablon_password_hash/' /var/www/html/biomaps/root-site/projects/sablon/private/private.map"
fi
