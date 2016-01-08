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
	echo -e "-s, --snap\tIn which <snap_path> to create the snap, must be in the <path> to backup"
	echo -e "-d, --backup\tWhere to do the backup (TAR of the snap, compress or not)"
	echo -e "-n, --nomount\tTell to not use the mount --bind option (default is to use it, to avoid multi-mount point backup)"
	echo -e "-N, --name\tGive a name to the backup, used to create the subdirectory hierarchy for snap/backup"
	echo -e "-l, --loglevel\tDefine the loglevel (DEBUG, INFO, WARNING, ERROR)"
	echo
}

#
# Function to log message
function log
{
	local level=${config[loglevel]}

	if [ ${loglevel[$1]} -ge ${loglevel[$level]} ]
	then
		local level=$1
		shift

		local message=$@
		shift

		local text="[`date '+%Y/%m/%d %H:%M:%S'`] - `date '+%s'` - ${level} - ${message}"

		echo $text
		echo $text > ${config[logfile]}
	fi
}

#
# Do not source a configuration file to avoid exploit... (source "rm -rf /" or "PS1=toto")
function load_configuration
{
	if [ "$CONF_FILE" != "" ]
	then
		log "INFO" "Loading configuration file : $CONF_FILE"
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
# Debug function, dump the config var
function dump
{
	for i in ${!config[@]}
	do
		echo "$i => ${config[$i]}"
	done
}

#
# Test that all parameters are good
function test_configuration
{
	if [ "${config[retention]}" -le 0 ]
	then
		log "WARNING" "the retention is to small, back to the minimal value"
		config[retention]=1
	fi

	if [ "${config[retention]}" -gt 16 ]
	then
		log "WARNING" "the retention is set to ${config[retention]}, it seems to be a lot"
	fi

	if [[ "${config[compress]}" != "gzip" ]] && [[ "${config[compress]}" != "bzip2" ]]
	then
		log "WARNING" "wrong type of compress tool, back to gzip"
		config[compress]="gzip"
	fi

	if [ ! -d "${config[snap]}" ]
	then
		log "ERROR" "SNAP directory ${config[snap]} doesn't exists"
		exit 1
	fi

	if [ ! -d ${config[backup]} ]
	then
		log "ERROR" "BACKUP directory ${config[backup]} doesn't exists"
		exit 1
	fi

	if [[ ${config[nomount]} -ne 0 ]] && [[ ${config[nomount]} -ne 1 ]]
	then
		log "WARNING" "Wrong value for nomount option, back to '0'"
		config[nomount]=0
	fi

	if [ ! -d $BCK_PATH ]
	then
		log "ERROR" "PATH to backup '${BCK_PATH}' doesn't exists"
		exit 1
	fi

	if [[ ${config[init]} -le 0 ]] && [[ ! -f "${BCK_PATH}/.${BCK_CONF}" ]]
	then
		log "ERROR" "PATH has not been 'init', please see the help"
		exit 1
	fi

	if [ -z "${config[name]}" ]
	then
		config[name]=`tr -cd '[:alnum:]' < /dev/urandom | fold -w12 | head -n 1`
		log "WARNING" "No name has been give, create random one: ${config[name]}"
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
	[name]=""
	[loglevel]="INFO"
)

#
# Log level
declare -A loglevel
loglevel=(
	[ERROR]=4
	[WARNING]=3
	[INFO]=2
	[DEBUG]=1
)

#--------------------------------------------------------
# Read config file if found

DIR=$(dirname $0)
DATE=`date '+%Y%m%d'`
CONF_FILE=""

#
# Check different path, last is the priority one
[ -f "${HOME}/.config/btrfs-backup/btrfs-backuprc" ] && CONF_FILE="${HOME}/.config/btrfs-backup/btrfs-backuprc"
[ -f "${DIR}/btrfs-backup.conf" ] && CONF_FILE="${DIR}/btrfs-backup.conf"

#--------------------------------------------------------
# Read command line parameters (overwrite the conf)

if ! options=$(getopt -o hc:r:ib:z:s:d:N:l:nv -l help,config:,retention:,init,rsync:,compress:,snap:,backup:,name:,loglevel:,nomount,version -- "$@")
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
		-N|--name)
			TMP_NAME="$2"
			shift
			;;
		-l|--loglevel)
			config[loglevel]="$2"
			shift
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

#########################################################
# Main program

#--------------------------------------------------------
# Manage configurtaion

#
# Load the configuration
load_configuration

#
# Apply parameters given in command line

[ -n "$TMP_RETENTION" ] && config[retention]="$TMP_RETENTION"
[ -n "$TMP_RSYNC" ] && config[rsync]="$TMP_RSYNC"
[ -n "$TMP_COMPRESS" ] && config[compress]="$TMP_COMPRESS"
[ -n "$TMP_SNAP" ] && config[snap]="$TMP_SNAP"
[ -n "$TMP_BACKUP" ] && config[backup]="$TMP_BACKUP"
[ -n "$TMP_NOMOUNT" ] && config[nomount]=1
[ -n "$TMP_NAME" ] && config[name]="$TMP_NAME"

#
# Test the configuration for errors
test_configuration

#--------------------------------------------------------
# Init a local configuration file ?

# Initial configuration, write a hidden file with configuration in it.
if [ ${config[init]} -gt 0 ]
then
	log "INFO" "Writing variables in ${BCK_PATH}/.${BCK_CONF}"
	echo "retention=${config[retention]}" > ${BCK_PATH}/.${BCK_CONF}
	echo "rsync=${config[rsync]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "compress=${config[compress]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "backup=${config[backup]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "snap=${config[snap]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "nomout=${config[nomount]}" >> ${BCK_PATH}/.${BCK_CONF}
	echo "name=${config[name]}" >> ${BCK_PATH}/.${BCK_CONF}

	exit 0
fi

#--------------------------------------------------------
# Mount bind if necessary

if [ ${config[nomount]} -le 0 ]
then
	TMP_MOUNT="`mktemp -d --tmpdir bindbtrfs-XXXXXXX`"

	mount --bind "${BCK_PATH}" "${TMP_MOUNT}"

	if [ $? -ne 0 ]
	then
		log "ERROR" "Error during the mount --bind command"
		exit 253
	fi
	FS_TO_BACKUP=${TMP_MOUNT}
else
	FS_TO_BACKUP=${BCK_PATH}
fi

#--------------------------------------------------------
# Trap signal to unconfigure temporary stuff

trap '
umount "$TMP_MOUNT" >/dev/null 2>&1
rmdir "$TMP_MOUNT"
' INT QUIT TERM EXIT

#--------------------------------------------------------
# Do the backup

if [ -d "${config[snap]}/${config[name]}" ]
then
	#
	#snap already exists, doing incremental backup

	# SNAP
	log "INFO" "Snapshot of the volume ${FS_TO_BACKUP} on ${config[snap]}/${config[name]}"
	btrfs subvolume snapshot -r ${FS_TO_BACKUP} "${config[snap]}/${config[name]}-new" 2>&1 > /dev/null
	if [ $? -ne 0 ]; then log "ERROR" "Error during the snapshot of ${FS_TO_BACKUP} on ${config[snap]}/${config[name]}" ; exit 10; fi
	sync

	# BACKUP
	log "INFO" "Backup of ${config[snap]}/${config[name]} on ${config[backup]}"
	btrfs send "${config[snap]}/${config[name]}-new" | btrfs receive "${config[backup]}"
	if [ $? -ne 0 ]; then log "ERROR" "Error during the backup of ${config[snap]}/${config[name]} on ${config[backup]}" ; exit 11; fi

	# Managing snap/backup
	log "INFO" "Removing old snapshot and replace it by the new one"
	btrfs subvolume delete "${config[snap]}/${config[name]}" 2>&1 > /dev/null
	mv "${config[snap]}/${config[name]}-new" "${config[snap]}/${config[name]}" 2>&1 > /dev/null

	log "INFO" "Rename backup folder from ${config[backup]}/${config[name]}-new to ${config[backup]}/${config[name]}"
	#btrfs subvolume delete "${config[backup]}/${config[name]}" 2>&1 > /dev/null
	mv "${config[backup]}/${config[name]}-new" "${config[backup]}/${config[name]}" 2>&1 > /dev/null
else
	#
	#first snap/backup
	log "INFO" "First snap and first backup (after init)."

	# SNAP
	log "INFO" "Snapshot of the volume ${FS_TO_BACKUP} on ${config[snap]}/${config[name]}"
	btrfs subvolume snapshot -r ${FS_TO_BACKUP} "${config[snap]}/${config[name]}" 2>&1 > /dev/null
	if [ $? -ne 0 ]; then log "ERROR" "Error during the snapshot of ${FS_TO_BACKUP} on ${config[snap]}/${config[name]}" ; exit 10; fi
	sync

	# BACKUP
	log "INFO" "Backup of ${config[snap]}/${config[name]} on ${config[backup]}"
	btrfs send "${config[snap]}/${config[name]}" | btrfs receive "${config[backup]}" 2>&1 > /dev/null
	if [ $? -ne 0 ]; then log "ERROR" "Error during the backup of ${config[snap]}/${config[name]} on ${config[backup]}" ; exit 11; fi
fi

#
# TAR
log "INFO" "Archive in tar the backup folder ${config[backup]}/${config[name]}"
tar cf "${config[backup]}/backup_${config[name]}_${DATE}.tar" "${config[backup]}/${config[name]}" 2>&1 > /dev/null
if [ $? -ne 0 ]; then log "ERROR" "Error during tar archive of directory : ${config[backup]}/${config[name]}" ; exit 20; fi

#
# Compress it
log "INFO" "Compress the tar archive ${config[backup]}/backup_${config[name]}_${DATE}.tar using ${config[compress]}"
${config[compress]} "${config[backup]}/backup_${config[name]}_${DATE}.tar" 2>&1 > /dev/null
if [ $? -ne 0 ]; then log "ERROR" "Error during compression of tar file : ${config[backup]}/backup_${config[name]}_${DATE}.tar" ; exit 21; fi

#
# Rsync it (if necessary)
if [ -n "${config[rsync]}" ]
then
	log "INFO" "Rsyncing the compressed tar to ${config[rsync]}"
	rsync "${config[backup]}/backup_${config[name]}_${DATE}".* ${config[rsync]} 2>&1 > /dev/null
	if [ $? -ne 0 ]; then log "ERROR" "Error during rsync of file ${config[backup]}/backup_${config[name]}_${DATE}.* to ${config[rsync]}" ; exit 30; fi
fi

#
# Apply retention
log "INFO" "Keep only the last ${config[retention]} backup(s)"
(ls ${config[backup]}/backup_${config[name]}_* -t | head -n ${config[retention]}; ls ${config[backup]}/backup_${config[name]}_*) | sort | uniq -u | xargs --no-run-if-empty rm

#
# Do some cleaning
log "INFO" "Cleaning files"
umount "$TMP_MOUNT" >/dev/null 2>&1
rmdir $TMP_MOUNT
btrfs subvolume delete "${config[backup]}/${config[name]}" 2>&1 > /dev/null

log "INFO" "Backup is finished successfully"
