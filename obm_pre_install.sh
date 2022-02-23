#!/bin/bash

# default service port
# port=9880
postgres_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32})

printf "BIOMAPS_POSTGRES_PASSWORD=$postgres_password\nGISDATA_POSTGRES_PASSWORD=$postgres_password" > .env

#sed -i "s/- 9890:80/- $port:80/" docker-compose.yml
