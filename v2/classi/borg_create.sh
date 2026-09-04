#!/bin/bash

############################################################################################################### Borg - Create
borg_create() {
  local loc_error=0;
  local preBorg="";
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

  case ${1,,} in
    "local")
      export BORG_REPO=${LOCAL_REPO};
      EXTRA_OPT=${BORG_OPT} ${LOCAL_OPT}
      unset BORG_RSH;
      ;;
    "remote")
      export BORG_RSH=${Repo_RSH};
      export BORG_REPO=$Repo_SSH;
      EXTRA_OPT=${BORG_OPT} ${REMOTE_OPT}
      ;;
    *)
      loc_error=1;
      error "Invalid local/remote value, skip getting repository info! Actual value: $1";
      exit 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg create ${EXTRA_OPT} ${BORG_EXCLUDE} ::${Backup_UID} ${BORG_PATH}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to create $1 backup: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "Skip $1 backup...";
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
