#!/usr/bin/env bash

set -Eeo pipefail
source log.sh

export LOGDIR="${BACKUP_DIR}/logs"
export DATETIME=`date +"%Y%m%d_%H%M%S"`

export matrix_verbosity=${BACKUP_MATRIX_VERBOSITY}
export verbosity=${BACKUP_VERBOSITY}
export ELEMENT_SERVER="${BACKUP_ELEMENT_SERVER}"
export ROOM_ID="${BACKUP_ROOM_ID}"
export ACCESS_TOKEN="${BACKUP_ACCESS_TOKEN}"

export PGHOST="${POSTGRES_HOST}"
export PGPORT="${POSTGRES_PORT}"
KEEP_MINS=${BACKUP_KEEP_MINS}
KEEP_DAYS=`expr $((${BACKUP_KEEP_DAYS} - 1))`
KEEP_WEEKS=`expr $(((${BACKUP_KEEP_WEEKS} * 7) + 1))`
KEEP_MONTHS=`expr $(((${BACKUP_KEEP_MONTHS} * 31) + 1))`
WEEK_DAY="${BACKUP_WEEK_DAY}"
MONTH_DAY="${BACKUP_MONTH_DAY}"

Log_Open

edebug "Starting To Setup Environment..."

HOOKS_DIR="/hooks"
if [ -d "${HOOKS_DIR}" ]; then
  on_error(){
    run-parts -a "error" "${HOOKS_DIR}"
  }
  trap 'on_error' ERR
fi

if [ "${POSTGRES_DB}" = "**None**" -a "${POSTGRES_DB_FILE}" = "**None**" ]; then
  eerror "You need to set the POSTGRES_DB or POSTGRES_DB_FILE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=${POSTGRES_PORT_5432_TCP_ADDR}
    POSTGRES_PORT=${POSTGRES_PORT_5432_TCP_PORT}
  else
    eerror "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" -a "${POSTGRES_USER_FILE}" = "**None**" ]; then
  eerror "You need to set the POSTGRES_USER or POSTGRES_USER_FILE environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" -a "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  eerror "You need to set the POSTGRES_PASSWORD or POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE environment variable or link to a container named POSTGRES."
  exit 1
fi

edebug "Starting To Process Variables..."

#Process vars
if [ "${POSTGRES_DB_FILE}" = "**None**" ]; then
  POSTGRES_DBS=$(echo "${POSTGRES_DB}" | tr , " ")
elif [ -r "${POSTGRES_DB_FILE}" ]; then
  POSTGRES_DBS=$(cat "${POSTGRES_DB_FILE}")
else
  eerror "Missing POSTGRES_DB_FILE file."
  exit 1
fi
if [ "${POSTGRES_USER_FILE}" = "**None**" ]; then
  export PGUSER="${POSTGRES_USER}"
elif [ -r "${POSTGRES_USER_FILE}" ]; then
  export PGUSER=$(cat "${POSTGRES_USER_FILE}")
else
  eerror "Missing POSTGRES_USER_FILE file."
  exit 1
fi
if [ "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
elif [ -r "${POSTGRES_PASSWORD_FILE}" ]; then
  export PGPASSWORD=$(cat "${POSTGRES_PASSWORD_FILE}")
elif [ -r "${POSTGRES_PASSFILE_STORE}" ]; then
  export PGPASSFILE="${POSTGRES_PASSFILE_STORE}"
else
  eerror "Missing POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE file."
  exit 1
fi

if [ $matrix_verbosity -gt 0 ]
then

    if [ "${BACKUP_ELEMENT_SERVER}" = "**None**" ]; then
      eerror "You need to set the BACKUP_ELEMENT_SERVER environment variable or set BACKUP_MATRIX_VERBOSITY to 0."
      exit 1
    fi

    if [ "${BACKUP_ROOM_ID}" = "**None**" ]; then
      eerror "You need to set the BACKUP_ROOM_ID environment variable or set BACKUP_MATRIX_VERBOSITY to 0."
      exit 1
    fi

    if [ "${BACKUP_ACCESS_TOKEN}" = "**None**" ]; then
      eerror "You need to set the BACKUP_ACCESS_TOKEN environment variable or set BACKUP_MATRIX_VERBOSITY to 0."
      exit 1
    fi

fi

edebug "...Finished Processing Variables"

# Pre-backup hook
if [ -d "${HOOKS_DIR}" ]; then
  run-parts -a "pre-backup" --exit-on-error "${HOOKS_DIR}"
fi

#Initialize dirs
FREQUENCY=( last daily weekly monthly )

for f in ${FREQUENCY[@]}
do

  mkdir -p "${BACKUP_DIR}/${f}/"

done

MONTH_DAY=`date +%d`
WEEK_DAY=`date +%A`

edebug "...Finished Setting Up Environment"

#Create Backups
create_backups () {

  edebug "${POSTGRES_DBS[@]}"

  for DB in ${POSTGRES_DBS}
  do

    edebug "Backing up Database: ${DB}"

    LAST_FILENAME="${DB}-`date +%Y%m%d-%H%M%S`${BACKUP_SUFFIX}"
    FILE="${BACKUP_DIR}/last/${LAST_FILENAME}"

    create_dump

    einfo "Point last backup file to this last backup..."
    ln -svf "${LAST_FILENAME}" "${BACKUP_DIR}/last/${DB}-latest${BACKUP_SUFFIX}"

    create_hardlinks "${FILE}" "daily"
    
    if [ "${BACKUP_MONTH_DAY}" = "${MONTH_DAY}" ]
    then

      create_hardlinks "${FILE}" "monthly"

    elif [ "${BACKUP_WEEK_DAY}" = "${WEEK_DAY}" ]
    then

      create_hardlinks "${FILE}" "weekly"

    fi

    einfo "SQL backup created successfully"

  done

  # Post-backup hook
  if [ -d "${HOOKS_DIR}" ]; then
    run-parts -a "post-backup" --reverse --exit-on-error "${HOOKS_DIR}"
  fi

}

#Create dump
create_dump () {

  if [ "${POSTGRES_CLUSTER}" = "TRUE" ]; then
    einfo "Creating cluster dump of ${DB} database from ${POSTGRES_HOST}..."
    pg_dumpall -l "${DB}" ${POSTGRES_EXTRA_OPTS} | gzip > "${FILE}" || echo ecrit "Postgres Dump Failed"
  else
    einfo "Creating dump of ${DB} database from ${POSTGRES_HOST}..."
    pg_dump -d "${DB}" -f "${FILE}" ${POSTGRES_EXTRA_OPTS} || echo ecrit "Postgres Dump Failed"
  fi

}

create_hardlinks () {
  
  SRC=$1
  INCREMENT=$2

  edebug "Source: ${SRC}"
  edebug "Increment: ${INCREMENT}"

  if [ "${INCREMENT}" = "daily" ]
  then

    FILENAME="${DB}-`date +%Y%m%d`${BACKUP_SUFFIX}"

  elif [ "${INCREMENT}" = "weekly" ]
  then

    FILENAME="${DB}-`date +%G%V`${BACKUP_SUFFIX}"

  elif [ "${INCREMENT}" = "monthly" ]
  then

    FILENAME="${DB}-`date +%Y%m`${BACKUP_SUFFIX}"

  fi

  DEST="${BACKUP_DIR}/${INCREMENT}/${FILENAME}"

  edebug "Destionation: ${DEST}"

  edebug "Creating Linking..."

  #Copy (hardlink) for each entry
  if [ -d "${SRC}" ]
  then
    DESTNEW="${DEST}-new"
    rm -rf "${DESTNEW}"
    mkdir "${DESTNEW}"
    ln -f "${SRC}/"* "${DESTNEW}/"
    rm -rf "${DEST}"
    einfo "Replacing ${INCREMENT} backup ${DEST} file this last backup..."
    mv "${DESTNEW}" "${DEST}"
  else
    einfo "Replacing ${INCREMENT} backup ${DEST} file this last backup..."
    ln -vf "${SRC}" "${DEST}"
  fi
  # Update latest symlinks
  einfo "Replacing lastest ${INCREMENT} backup to this last backup..."
  ln -svf "${DEST}" "${BACKUP_DIR}/${INCREMENT}/${DB}-latest"

  edebug "...Link has been created"

}

#Clean up old backups
cleanup_backups () {

  einfo "Starting to clean up old backups..."
  
  for folder in "${FREQUENCY[@]}"
  do
    if [ $folder == 'last' ]
    then
      time=$KEEP_MINS
      unit="minutes"
      keep=1
    elif [ $folder == 'daily' ]
    then
      time=$KEEP_DAYS
      unit="days"
      keep=(${KEEP_DAYS})
    elif [ $folder == "weekly" ]
    then
      time=$KEEP_WEEKS
      unit="days"
      keep=`expr $(((${KEEP_WEEKS} - 1) / 7))`
    elif [ $folder == 'monthly' ]
    then
      time=$KEEP_MONTHS
      unit="days"
      keep=`expr $(((${KEEP_MONTHS} - 1) / 31))`
    fi

    edebug "Keeping $keep backups over the past $time $unit"

    if [[ $time -gt 0 ]]
    then
    
      for DB in ${POSTGRES_DBS}
      do

        #Clean old files
        edebug "Cleaning up backups of $DB database..."
        local all=( `find "${BACKUP_DIR}/${folder}" -maxdepth 1 -name "${DB}-*" | sort -t/ -k3` )
        local files=()
        number=$((${#all[@]}-$keep))
        einfo "Number of Backups to be deleted: $number"

        if [[ $number -lt 0 ]]
        then
          
          ecrit "Only ${#all[@]} Backups exist for ${DB} and you want to keep $keep."
          ecrit "If you have just started taking backups you may ignore this"
          ecrit "Otherwise you may want to investigate why backups are not being taken"

        elif [[ $number -gt 0 ]]
        then

          edebug "Getting Current Time and Date"
          local date=$(date +%Y%m%d --date "$time $unit ago")
          date=$(date -d "$date")
          einfo "Cleaning files older than $date in ${folder} for ${DB} database from ${POSTGRES_HOST}..."
          date=$(date -d "$date" +%s)
        
          for backup in ${all[@]}
          do

            edebug "Checking Modified Date of Backup"
            local filemod=$(date -r "$backup" +%s)
            einfo "Checking Backup: $backup"
            einfo "File Last Modified: $(date -r $backup)"

            if [[ $date -ge $filemod ]]
            then

              edebug "Mark Backup for Deletion"
              files=( $backup )

              ((number--))

            fi

            if [[ $number -le 0 ]]
            then

              edebug "...All Extra Backups have been marked for deletion"
              break

            fi

          done

        fi

    	  if [ "${#files[@]}" -gt 0 ]
        then

          for file in "${files[@]}"
          do

            einfo "Deleting Backup: $file"
      		  rm -r $file

          done
        
        fi

      done

    fi

  done
}

for arg in "$@"; do
    case $arg in
    -a)
        einfo "Starting Backup..."
        create_backups
        cleanup_backups
        ;;
    -b)
        einfo "Starting Backup..."
        create_backups
        ;;
    -c)
        einfo "Starting Cleanning Up Old Backups..."
        cleanup_backups
        ;;
    *)
        einfo "Starting Backup..."
        create_backups
        cleanup_backups
        ;;
    esac
done

edebug "...Backup Finished"

Log_Close