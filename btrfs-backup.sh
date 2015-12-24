#!/usr/bin/env bash

#########################################################
# Usefull functions

#
# Function that give the usage for the help
function usage
{
	echo "$0 [-h|--help] [-v|--version] [-r|--retention number] [-i|--init] [-b|--rsync rsync_path] [-z|--compress extension] [-s|--snap snap_path] [-d|--backup backup_path] [-n|--nomount] path"
	echo
	echo -e "-h, --help\tPrint this help"
	echo -e "-v, --version\tPrint the version of this script"
	echo -e "-r, --retention\tTell the script to kept <number> of snap (minimum 1 to have incremental)"
	echo -e "-i, --init\tInitialize the procedure for a path to snap/backup/rsync/..."
	echo -e "-b, --rsync\tAn optional path to rsync the backup (copy the TAR file)"
	echo -e "-z, --compress\tCompressor to choose for the TAR (backup) file (gzip/bzip2)"
	echo -e "-s, --snap\tIn which <snap_path> to create the snap"
	echo -e "-d, --backup\tWhere to do the backup (TAR of the snap, compress or not)"
	echo -e "-n, --nomount\tTell to not use the mount --bind option (default is to use it, to avoid multi-mount point backup)"
	echo
}

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

#
# Do not source a configuration file to avoid exploit... (source "rm -rf /" or "PS1=toto")
function load_configuration
{
	if [ "$CONF_FILE" != "" ]
	then
		while read line
		do
			if echo $line | grep -F = &>/dev/null
			then
				varname=$(echo "$line" | cut -d '=' -f 1)
				config[$varname]=$(echo "$line" | cut -d '=' -f 2-)
			fi
		done < $CONF_FILE
	fi
}

#
# Test that all parameters are good
function test_configuration
{
	if [ "${config[retention]}" -le 0 ]
	then
		log WARNING "the retention is to small to do incremental backup"
	fi

	if [ "${config[retention]}" -gt 16 ]
	then
		log WARNING "the retention is set to ${config[retention]}, it seems to be a lot"
	fi

	if [[ "${config[compress]}" != "gzip" ]] && [[ "${config[compress]}" != "bzip2" ]]
	then
		log WARNING "wrong type of compress tool, back to gzip"
		config[compress]="gzip"
	fi

	if [ ! -d "${config[snap]}" ]
	then
		log ERROR "SNAP directory ${config[snap]} doesn't exists"
		exit 1
	fi

	if [ ! -d ${config[backup]} ]
	then
		log ERROR "BACKUP directory ${config[backup]} doesn't exists"
		exit 1
	fi

	if [[ ${config[nomount]} -ne 0 ]] && [[ ${config[nomount]} -ne 1 ]]
	then
		log WARNING "Wrong value for nomount option, back to '0'"
		config[nomount]=0
	fi

	if [ ! -d $BCK_PATH ]
	then
		log ERROr "PATH to backup '${BCK_PATH}' doesn't exists"
		exit 1
	fi
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
	[version]="v0.1"
	[retention]=1
	[init]=0
	[rsync]=""
	[compress]="gzip"
	[snap]="/snap"
	[backup]="/backup"
	[nomount]=0
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

#--------------------------------------------------------
# Read config file if found

DIR=$(dirname $0)
CONF_FILE=""

#
# Check different path, last is the priority one
[ -f "${HOME}/.config/btrfs-backup/btrfs-backuprc" ] && CONF_FILE="${HOME}/.config/btrfs-backup/btrfs-backuprc"
[ -f "${DIR}/btrfs-backup.conf" ] && CONF_FILE="${DIR}/btrfs-backup.conf"

#--------------------------------------------------------
# Read command line parameters (overwrite the conf)

if ! options=$(getopt -o hc:r:ib:z:s:d:nv -l help,config:,retention:,init,rsync:,compress:,snap:,backup:,nomount,version -- "$@")
then
	exit 1
fi

while [ $# -gt 0 ]
do
	case $1 in
		-h|--help)
			usage
			exit 0
			;;
		-v|--version)
			echo "$0 version ${config[version]}"
			exit 0
			;;
		-c|--config)
			CONF_FILE="$2"
			shift
			;;
		-r|--retention)
			TMP_RETENTION="$2"
			shift
			;;
		-i|--init)
			config[init]=1
			;;
		-b|--rsync)
			TMP_RSYNC=$2
			shift
			;;
		-z|--compress)
			TMP_COMPRESS=$2
			shift
			;;
		-s|--snap)
			TMP_SNAP=$2
			shift
			;;
		-d|--backup)
			TMP_BACKUP="$2"
			shift
			;;
		-n|--nomount)
			TMP_NOMOUNT=1
			;;
		(--)
			break;;
		(-*)
			echo "$0: error - unrecognized option $1" 1>&2
			exit 1
			;;
		(*)
			break
			;;
	esac
	shift
done

BCK_PATH=$1
BCK_CONF=`basename $0 .sh`

[ -f ${BCK_PATH}/.${BCK_CONF} ] && [ ${config[init]} -le 0 ] && CONF_FILE="${BCK_PATH}/.${BCK_CONF}"

echo $BCK_PATH

#########################################################
# Main program

#--------------------------------------------------------
# Manage configurtaion

#
# Load the configuration
load_configurationa

#
# Apply parameters given in command line

[ -n "$TMP_RETENTION" ] && config[retention]="$TMP_RETENTION"
[ -n "$TMP_RSYNC" ] && config[rsync]="$TMP_RSYNC"
[ -n "$TMP_COMPRESS" ] && config[compress]="$TMP_COMPRESS"
[ -n "$TMP_SNAP" ] && config[snap]="$TMP_SNAP"
[ -n "$TMP_BACKUP" ] && config[backup]="$TMP_BACKUP"
[ -n "$TMP_NOMOUNT" ] && config[nomount]=1

#
# Test the configuration for errors
test_configuration

#--------------------------------------------------------
# Init a local configuration file ?

# Initial configuration, write a hidden file with configuration in it.
if [ ${config[init]} -gt 0 ]
then
echo $BCK_PATH
	log INFO "Writing variables in ${BCK_PATH}/.${BCK_CONF}"
	echo "retention=${config[retention]}" > ${BCK_PATH}/.${BCK_CONF}
	echo "rsync=${config[rsync]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "backup=${config[backup]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "snap=${config[snap]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "nomount=${config[nomount]}" >> ${BCK_PATH}/.${BCK_CONF}

	exit 0
fi


