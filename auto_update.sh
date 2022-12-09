# A shell script to fetch docker updates automatically
# Run this from cron

cd /srv/docker/openbiomaps/obm-composer
/usr/local/bin/docker-compose pull
/usr/local/bin/docker-compose up -d
