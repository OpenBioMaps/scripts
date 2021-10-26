docker-compose exec gisdata pg_dump -U biomapsadmin biomaps > biomaps.dump
docker-compose exec gisdata pg_dump -U biomapsadmin gisdata > gisdata.dump
bzip2 biomaps.dump
bzip2 gisdata.dump
sudo tar -czf knp-docker.tar.gz /srv/docker/openbiomaps/obm-composer

scp biomaps.dump.bz2 knpi@dhtecloud.mooo.com:archive/
scp gisdata.dump.bz2 knpi@dhtecloud.mooo.com:archive/
scp knp-docker.tar.gz knpi@dhtecloud.mooo.com:archive/
