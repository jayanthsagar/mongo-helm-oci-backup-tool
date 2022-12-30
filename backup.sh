#!/bin/bash

export TIMESTAMP="$(date "+%Y-%m-%d-%H:%M:%S")"
if [ -z $MONGO_ADDR ]; then
  echo "You must specify a MONGO_ADDR env var with port, such as my-mongo:27017"
  exit 1
fi

if [ -z $DATABASE ]; then
  echo "You must specify a DATABASE env var; comma-separated list of databases to backup"
  exit 1
fi

if [ -z $CLOUD_PROVIDER ]; then
  echo "You must specify a CLOUD_PROVIDER env var"
  exit 1
fi

if [ -z $BUCKET ]; then
  echo "You must specify a BUCKET address such as (gs|s3)://my-backups"
  exit 1
fi

if [ -z $HEAP_SIZE ]; then
  export HEAP_SIZE=2G
fi

if [ -z $PAGE_CACHE ]; then
  export PAGE_CACHE=2G
fi

if [ -z $FALLBACK_TO_FULL ]; then
  export FALLBACK_TO_FULL="true"
fi

if [ -z $CHECK_CONSISTENCY ]; then
  export CHECK_CONSISTENCY="true"
fi

if [ -z $CHECK_INDEXES ]; then
  export CHECK_INDEXES="true"
fi

if [ -z $CHECK_GRAPH ]; then
  export CHECK_GRAPH="true"
fi

if [ -z $CHECK_LABEL_SCAN_STORE ]; then
  export CHECK_LABEL_SCAN_STORE="true"
fi

if [ -z $CHECK_PROPERTY_OWNERS ]; then
  export CHECK_PROPERTY_OWNERS="false"
fi

if [ -z $REMOVE_EXISTING_FILES ]; then
  export REMOVE_EXISTING_FILES="true"
fi

if [ -z $REMOVE_BACKUP_FILES ]; then
  export REMOVE_BACKUP_FILES="true"
fi

function clean_backups_directory() {
  echo "Removing any existing files from /backups"
  rm -rfv /backups/*
}

function cloud_copy() {
  backup_path=$1
  database=$2
  artifact_type=$3

  bucket_path=""
  if [ "${BUCKET: -1}" = "/" ]; then
      bucket_path="${BUCKET%?}/$database"
  else
      bucket_path="$BUCKET/$database"
  fi

  echo "Pushing $backup_path -> $bucket_path"

  case $CLOUD_PROVIDER in
  aws)
    aws s3 cp $backup_path $bucket_path
    if [ "${artifact_type}" = "backup" ]; then
      aws s3 cp $backup_path "${bucket_path}${LATEST_POINTER}"
    fi
    ;;
  oci)
    /root/bin/oci os object put -ns $NAMESPACE -bn $BUCKET --file $backup_path --name "${database}/${backup_path}" --force
    if [ "${artifact_type}" = "backup" ]; then
      /root/bin/oci os object put -ns $NAMESPACE -bn $BUCKET --file $backup_path --name "${database}/${LATEST_POINTER}" --force
    fi
    ;;
  gcp)
    gsutil cp $backup_path $bucket_path
    if [ "${artifact_type}" = "backup" ]; then
      gsutil cp $backup_path "${bucket_path}${LATEST_POINTER}"
    fi
    ;;
  azure)
    # Container is specified via BUCKET input, which can contain a path, i.e.
    # my-container/foo
    # AZ CLI doesn't allow this so we need to split it into container and container path.
    IFS='/' read -r -a pathParts <<< "$BUCKET"
    CONTAINER=${pathParts[0]}

    # See: https://stackoverflow.com/a/10987027
    CONTAINER_PATH=${BUCKET#$CONTAINER}
        
    CONTAINER_FILE=$CONTAINER_PATH/$database/$(basename "$backup_path")
    # Remove all leading and doubled slashes to avoid creating empty folders in azure
    CONTAINER_FILE=$(echo "$CONTAINER_FILE" | sed 's|^/*||')
    CONTAINER_FILE=$(echo "$CONTAINER_FILE" | sed s'|//|/|g')

    echo "Azure storage blob copy to $CONTAINER :: $CONTAINER_FILE"
    az storage blob upload --container-name "$CONTAINER" \
                       --file "$backup_path" \
                       --name $CONTAINER_FILE \
                       --account-name "$ACCOUNT_NAME" \
                       --account-key "$ACCOUNT_KEY" \
                       --overwrite "true"

    if [ "${artifact_type}" = "backup" ]; then
      latest_name=$CONTAINER_PATH/$database/${LATEST_POINTER}
      # Remove all leading and doubled slashes to avoid creating empty folders in azure
      latest_name=$(echo "$latest_name" | sed 's|^/*||')
      latest_name=$(echo "$latest_name" | sed s'|//|/|g')

      echo "Azure storage blob copy to $CONTAINER :: $latest_name"
      az storage blob upload --container-name "$CONTAINER" \
                             --file "$backup_path" \
                             --name "$latest_name" \
                             --account-name "$ACCOUNT_NAME" \
                             --account-key "$ACCOUNT_KEY"
    fi
    ;;
  esac
}

function upload_report() {
  echo "Archiving and Compressing -> ${REPORT_DIR}/$BACKUP_SET.tar"

  tar -zcvf "backups/$BACKUP_SET.report.tar.gz" "${REPORT_DIR}" --remove-files

  if [ $? -ne 0 ]; then
    echo "REPORT ARCHIVING OF ${REPORT_DIR} FAILED"
    exit 1
  fi

  echo "Zipped report size:"
  du -hs "/backups/$BACKUP_SET.report.tar.gz"

  cloud_copy "/backups/$BACKUP_SET.report.tar.gz" $db "report"

  if [ $? -ne 0 ]; then
    echo "Storage copy of report for ${REPORT_DIR} FAILED"
    exit 1
  else
    echo "Removing /backups/$BACKUP_SET.report.tar.gz"
    rm "/backups/$BACKUP_SET.report.tar.gz"
  fi
}

function backup_database() {
  db=$1

  export REPORT_DIR="/backups/.report_$db"
  mkdir -p "${REPORT_DIR}"
  echo "Removing any existing files from ${REPORT_DIR}"
  rm -rfv "${REPORT_DIR}"/*

  export BACKUP_SET="$db-${TIMESTAMP}"
  export LATEST_POINTER="$db-latest.tar.gz"

  echo "=============== BACKUP $db ==================="
  echo "Beginning backup from $MONGO_ADDR to /backups/$BACKUP_SET"
  echo "Using heap size $HEAP_SIZE and page cache $PAGE_CACHE"
  echo "FALLBACK_TO_FULL=$FALLBACK_TO_FULL, CHECK_CONSISTENCY=$CHECK_CONSISTENCY"
  echo "CHECK_GRAPH=$CHECK_GRAPH CHECK_INDEXES=$CHECK_INDEXES"
  echo "CHECK_LABEL_SCAN_STORE=$CHECK_LABEL_SCAN_STORE CHECK_PROPERTY_OWNERS=$CHECK_PROPERTY_OWNERS"
  echo "To storage bucket $BUCKET using $CLOUD_PROVIDER"
  echo "============================================================"

  set -ex
  apt update
  apt install wget
  wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-debian10-x86_64-100.5.2.deb
  dpkg -i mongodb-database-tools-debian10-x86_64-100.5.2.deb
  sleep 5
  backup_filename="mongobackup_"$(date +"%d.%m.%y-%H-%M-%S")
  echo -e "\nBacking Up ..."
  mongodump -h ${MONGO_HOST} -p ${MONGO_PORT} -u ${MONGO_ADMIN_USER} -p ${MONGOPASSWORD} -o ${backup_filename} -v
  if [[ $? != 0 ]]
  then
      echo "Exiting......"
      exit
  fi
  sleep 10
  echo -e "\nFinished Backup"
  echo "Backup size:"
  du -hs ${backup_filename}

  echo "Final Backupset files"
  ls -l ${backup_filename}
  tar -czf ${backup_filename}".tar.gz" ${backup_filename}
  

  echo "Zipped backup size:"
  du -hs ${backup_filename}".tar.gz"

  cloud_copy ${backup_filename}".tar.gz" $db "backup"

}

function activate_gcp() {
  local credentials="/credentials/credentials"
  if [[ -f "${credentials}" ]]; then
    echo "Activating google credentials before beginning"
    gcloud auth activate-service-account --key-file "${credentials}"
    if [ $? -ne 0 ]; then
      echo "Credentials failed; no way to copy to google."
      exit 1
    fi
  else
    echo "No credentials file found. Assuming workload identity is configured"
  fi
}

function activate_aws() {
  local credentials="/credentials/credentials"
  if [[ -f "${credentials}" ]]; then
    echo "Activating aws credentials before beginning"
    mkdir -p /root/.aws/
    cp /credentials/credentials ~/.aws/config
    if [ $? -ne 0 ]; then
      echo "Credentials failed; no way to copy to aws."
      exit 1
    fi
    aws sts get-caller-identity
    if [ $? -ne 0 ]; then
      echo "Credentials failed; no way to copy to aws."
      exit 1
    fi
  else
    echo "No credentials file found. Assuming IAM Role for Service Account - IRSA is configured"
  fi
}

function activate_oci() {
  local credentials="/credentials/credentials"
  local pemkey = "/pemkey/pemkey"
  if [[ -f "${credentials}" ]]; then
    echo "Activating oci credentials before beginning"
    mkdir -p /root/.oci/
    cp /credentials/credentials ~/.oci/config
    cp /pemkey/pemkey ~/.oci/OCIkey.pem
    if [ $? -ne 0 ]; then
      echo "Credentials failed; no way to copy to OCI."
      exit 1
    fi
  else
    echo "No credentials file found."
  fi
}

function activate_azure() {
  echo "Activating azure credentials before beginning"
  source "/credentials/credentials"

  if [ -z $ACCOUNT_NAME ]; then
    echo "You must specify a ACCOUNT_NAME export statement in the credentials secret which is the storage account where backups are stored"
    exit 1
  fi

  if [ -z $ACCOUNT_KEY ]; then
    echo "You must specify a ACCOUNT_KEY export statement in the credentials secret which is the storage account where backups are stored"
    exit 1
  fi
}

if [ "${REMOVE_EXISTING_FILES}" == "true" ]; then
  clean_backups_directory
fi

case $CLOUD_PROVIDER in
azure)
  activate_azure
  ;;
aws)
  activate_aws
  ;;
gcp)
  activate_gcp
  ;;
oci)
  activate_oci
  ;;
*)
  echo "Invalid CLOUD PROVIDER=$CLOUD_PROVIDER"
  echo "You must set CLOUD_PROVIDER to be one of (aws|gcp|oci|azure)"
  exit 1
  ;;
esac

# Split by comma
IFS=","
read -a databases <<<"$DATABASE"
for db in "${databases[@]}"; do
  backup_database "$db"
done

echo "All finished"
exit 0
