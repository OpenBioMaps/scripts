# Cron script for auto-update and OBM instance

cd /srv/docker/openbiomaps/obm-composer
/usr/local/bin/docker-compose pull
/usr/local/bin/docker-compose up -d
