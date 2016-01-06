#!/usr/bin/env bash

#################################################
#/!\
#/!\ ALL FS NEED TO BE INIT
#/!\
#/!\ c.f. ./btrfs-backup --help
#/!\
#################################################

#################################################
# Variables

DIR=`realpath ks001-backup | xargs dirname`
BKP="${DIR}/btrfs-backup.sh"

declare -a FS
FS=(
	'/'
	'/usr'
	'/var'
	'/home'
	'/opt'
	'/data/mysql'
	'/data/gitlab'
	'/data/opentsdb'
	'/data/splunk'
	'/srv/apache'
	'/srv/ossec'
)

#################################################
# Main program


#
# Do the backup
for fs in "${FS[@]}"
do
	${BKP} ${fs} >> /var/log/backup.log
done

#
# Do remote cleaning, for now in this script, later in the btrfs-backup.sh
ssh mutu -- "~/backup/ks001/clean.sh"
