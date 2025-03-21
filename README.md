# scripts
Useful scripts for OBM development and management

## findre.pl

Find recursively for code parts, like variables.

It just uses the find command with lots of arguments.

If you only look for words in a single directory use grep instead of this.

## obm_archive.sh

Use this to set a periodical SQL dump of your important tables.

Example cron:
```
0 2 * * * /home/user/Scripts/obm_archive.sh normal
15 3 1 * * /home/user/Scripts/obm_archive.sh full
# Cleaning the local archive
0 5 * * * /home/user/Scripts/obm_archive.sh clean
# Syncing with ssh to remote servers
0 4 * * * /home/user/Scripts/obm_archive.sh sync user@remote.server.org /home/archives/local_server.org_archive
# Syncing with curl to remote servers (e.g. Nextcloud)
0 4 * * * /home/users/scripts/obm_archive.sh curl-sync dsusTsl92772easd: https://nextcloud.remote-server.org/public.php/webdav/
```

## create_table_from_csv.R

CML R script to create ALTER TABLE... SQL lines to extend an existing database table with several new columns.
It analyses the column contents and automatically sets the proper SQL column types

## import.pl export.pl

CML perl tool: php language definition files import/export from/to CSV

## obm_git_sync_to_obm_server.sh

bash script including rsync commands to update OBM server from the local repository. E.g. from git to server after some local test of new commits.

## extract_obm_backup (python version by Gabor)

python script for extracting data from mobile_app backup files.

Requires python 3.7

 `cd extract_obm_backup`\
 `virtualenv --clear -p /usr/local/bin/python3.7 venv`\
 `source venv/bin/activate`\
 `pip install -r requirements.txt` \
  `python extract_data.py /path/to/backup.file`
  
Edit the settings.py file with your server url and project name.
 
The resulting csv files will be in the output folder, one file for each upload form.

## obm_backup_process (sh+php+R version by Miki)

bash & php scripts to process obm-mobile-app backup files. It is listing / summarize backup contents

Usage: 
1) ./obm_backup_process.sh obm_1651822616.json
```
-rw-r--r-- 1 banm banm  48040 máj   19 08.53 191_data.json
-rw-r--r-- 1 banm banm      3 máj   19 08.53 192_data.json
-rw-r--r-- 1 banm banm      3 máj   19 08.53 188_data.json
```
2) php obm_backup_process.php 191 191_data.json
```
-rw-r--r-- 1 banm banm    153 máj   19 09.52 form_191_row_9.csv
-rw-r--r-- 1 banm banm    157 máj   19 09.52 form_191_row_8.csv
-rw-r--r-- 1 banm banm    155 máj   19 09.52 form_191_row_7.csv
-rw-r--r-- 1 banm banm    156 máj   19 09.52 form_191_row_6.csv
-rw-r--r-- 1 banm banm    155 máj   19 09.52 form_191_row_5.csv
-rw-r--r-- 1 banm banm    155 máj   19 09.52 form_191_row_4.csv
-rw-r--r-- 1 banm banm    155 máj   19 09.52 form_191_row_3.csv
-rw-r--r-- 1 banm banm    158 máj   19 09.52 form_191_row_2.csv
-rw-r--r-- 1 banm banm    154 máj   19 09.52 form_191_row_1.csv
```

3) csvstack form_191_row_* > form_191_2022.05.06.csv

   OR 

   obm_backup_process.R 191

## tracklog process

tracklog export processing for upload

## docker_postgres_upgrade

Semiautomated upgrade solution for PostgreSQL databases in Docker containers.

#### Usage
```./docker_postgres_upgrade.sh <command> [db_container_name]```

#### Commands
- **testupgrade**: Tests upgrade without stopping services.
- **upgrade**: Performs production upgrade after confirmation.

**Note:** Use `upgrade` only after successful `testupgrade`.
