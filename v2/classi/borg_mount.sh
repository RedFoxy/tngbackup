#!/bin/bash

############################################################################################################### Borg - Mount
borg_mount() {
  local loc_error=0;
  local preBorg="";
  local MOUNT_POINT="";
  local operation="mount"
  local step_start=$(date "+%s")
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

  # Check if MOUNT_PATH is defined
  if [ -z "$MOUNT_PATH" ]; then
    loc_error=1;
    error "MOUNT_PATH is not defined, cannot mount repository!";
    return 1;
  fi

  MOUNT_POINT=$MOUNT_PATH;

  log "INFO" "Starting repository mount for $1 at ${MOUNT_POINT}..."

  case ${1,,} in
    "local")
      export BORG_REPO=${LOCAL_REPO};
      unset BORG_RSH;
      ;;
    "remote")
      export BORG_RSH=${Repo_RSH};
      export BORG_REPO=$Repo_SSH;
      ;;
    *)
      loc_error=1;
      error "Invalid local/remote value, cannot mount repository! Actual value: $1";
      return 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg mount ${BORG_REPO} ${MOUNT_POINT}"
    if [ $RUN_ERR -gt 0 ]; then
      local step_end=$(($(date "+%s") - step_start))
      error "Failed to mount $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "";
      audit_log "$operation" "FAILED" "mount failed for $1 repository at ${MOUNT_POINT}" "$step_end"

      case ${1,,} in
        "local")
          Local_SKIP=1;
          ;;
        "remote")
          Remote_SKIP=1;
          ;;
      esac
      return 1;
    else
      local step_end=$(($(date "+%s") - step_start))
      log "INFO" "Repository mount completed successfully for $1 at ${MOUNT_POINT}"
      audit_log "$operation" "SUCCESS" "mount completed for $1 repository at ${MOUNT_POINT}" "$step_end"
      return 0;
    fi
  fi
  return 1;
}
