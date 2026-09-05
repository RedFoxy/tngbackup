#!/bin/bash

############################################################################################################### Borg - Mount
borg_mount() {
  local loc_error=0;
  local preBorg="";
  local MOUNT_POINT="";
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

  # Check if MOUNT_PATH is defined
  if [ -z "$MOUNT_PATH" ]; then
    loc_error=1;
    error "MOUNT_PATH is not defined, cannot mount repository!";
    return 1;
  fi

  MOUNT_POINT=$MOUNT_PATH;

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
      exit 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg mount ${BORG_REPO} ${MOUNT_POINT}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to mount $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "";

      case ${1,,} in
        "local")
          Local_SKIP=1;
          ;;
        "remote")
          Remote_SKIP=1;
          ;;
      esac
    fi
  fi
}
