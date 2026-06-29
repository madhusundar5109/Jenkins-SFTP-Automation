#!/bin/bash

SOURCE_FOLDER="/home/client/sftp-test-client/"
JENKINS_URL="<Jenkins url>"
JENKINS_JOB="<Jenkins job>"
JENKINS_USER="<Jenkins user>"
JENKINS_TOKEN="<your-api-token>"

inotifywait -m -e close_write,moved_to --format '%f' -q "$SOURCE_FOLDER" \
  | while read FILENAME; do
      FILEPATH="${SOURCE_FOLDER}${FILENAME}"
      echo "[watcher] Detected: $FILEPATH"

      curl -s -X POST \
        "${JENKINS_URL}/job/${JENKINS_JOB}/buildWithParameters?CHANGED_FILE=${FILEPATH}" \
        --user "${JENKINS_USER}:${JENKINS_TOKEN}"

      echo "[watcher] Triggered Jenkins for: $FILEPATH"
  done
