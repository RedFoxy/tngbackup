#!/bin/bash

############################################################################################################### Borg - Info
borg_info() {
  local loc_error=0;
  local preBorg="";
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

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
      error "Invalid local/remote value, skip getting repository info! Actual value: $1";
      exit 1;
      ;;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg info"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to get info from $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "Skip $1 backup...";
      error "";

      case ${1,,} in
        "local")
          Local_SKIP=1;;
        "remote")
          Remote_SKIP=1;;
      esac
    fi
  fi

  unset BORG_PASSPHRASE;
  unset BORG_RSH;
  unset BORG_REPO;
}
