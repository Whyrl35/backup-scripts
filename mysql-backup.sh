#!/bin/bash

#########################################################
# Usefull functions

#
# Function to log message
function log
{
	local level=$1
	shift

	local message=$@
	shift

	local text="[`date '+%Y/%m/%d %H:%M:%S'`] - `date '+%s'` - ${level} - ${message}"

	echo $text
	echo $text > ${config[logfile]}
}

#########################################################
# Configuration

#--------------------------------------------------------
# Default Values

#
# Config var
declare -A config
config=(
	[logfile]=/dev/null
	[version]="v1.0"
	[retention]=10
	[rsync]="mutu:~/backup/sql/"
	[compress]="/bin/gzip -f "
	[backup]="/srv/backup/ks001/sql"
	[password]="/srv/backup/backup-scripts/.mysql-passwd"
)

#
# Log level
function ERROR
{
	echo "ERROR"
}

function WARNING
{
	echo "WARNING"
}

function INFO
{
	echo "INFO"
}

function DEBUG
{
	echo "DEBUG"
}

#
# Date, to tag the backup
DATE=`date '+%Y%m%d'`

#########################################################
# Main program

#
# List all the database
LISTEBDD=$( echo 'show databases' | mysql -u root -p`cat ${config[password]}` )

#
# Iterate on each database
for SQL in ${LISTEBDD}
do
	# Skipping mysql default database
	if [ "$SQL" != "information_schema" ] && [ "$SQL" != "mysql" ] && [ "$SQL" != "Database" ] && [ "$SQL" != "performance_schema" ]
	then
		# Do the backup
		log INFO "Dumping : $SQL"
		mysqldump -u root -p`cat ${config[password]}` "$SQL" > "${config[backup]}/${SQL}_mysql_${DATE}.sql"

		# Compress it
		log INFO "Compressing : ${config[backup]}/${SQL}_mysql_${DATE}.sql"
		${config[compress]} "${config[backup]}/${SQL}_mysql_${DATE}.sql"

		# Copy the backup file with rsync if needed
		if [ -n "${config[rsync]}" ]
		then
			log INFO "Rsync on ${config[rsync]} : ${config[backup]}/${SQL}_mysql_${DATE}.sql"
			rsync ${config[backup]}/${SQL}_mysql_${DATE}.* ${config[rsync]}
		fi

		# Keep only the 'retention' number of backup
		log INFO "Keeping only the ${config[retention]} number of file"
		(ls ${config[backup]}/${SQL}_mysql_* -t | head -n ${config[retention]}; ls ${config[backup]}/${SQL}_mysql_*) | sort | uniq -u | xargs --no-run-if-empty rm
	fi
done
