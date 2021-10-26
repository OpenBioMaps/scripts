#!/bin/bash

cd /opt/openbiomaps

./obm_pre_install.sh

docker-compose up -d

./obm_post_install.sh 
