#!/bin/bash

############################################################################################################### Borg - Prune
borg_prune() {
  local loc_error=0;
  local preBorg="";
  local PRUNE_OPT=""

  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

  case ${1,,} in
    "local")
      if [[ $LOCAL_KEEP_LAST > 0 ]]; then
        PRUNE_OPT=" --keep-last=$LOCAL_KEEP_LAST";
      else
        if [[ $LOCAL_KEEP_HOURLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$LOCAL_KEEP_HOURLY";   fi
        if [[ $LOCAL_KEEP_DAILY   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$LOCAL_KEEP_DAILY";     fi
        if [[ $LOCAL_KEEP_WEEKLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$LOCAL_KEEP_WEEKLY";   fi
        if [[ $LOCAL_KEEP_MONTHLY > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$LOCAL_KEEP_MONTHLY"; fi
        if [[ $LOCAL_KEEP_YEARLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$LOCAL_KEEP_YEARLY";   fi
      fi

      if [[ "$PRUNE_OPT" == "" ]]; then
        loc_error=1;
        error "No valid prune option, skip prune!";
      else
        export BORG_REPO=${LOCAL_REPO};
        unset BORG_RSH;
      fi
      ;;
    "remote")
      if [[ $REMOTE_KEEP_LAST > 0 ]]; then
        PRUNE_OPT=" --keep-last=$REMOTE_KEEP_LAST";
      else
        if [[ $REMOTE_KEEP_HOURLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$REMOTE_KEEP_HOURLY";   fi
        if [[ $REMOTE_KEEP_DAILY   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$REMOTE_KEEP_DAILY";     fi
        if [[ $REMOTE_KEEP_WEEKLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$REMOTE_KEEP_WEEKLY";   fi
        if [[ $REMOTE_KEEP_MONTHLY > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$REMOTE_KEEP_MONTHLY"; fi
        if [[ $REMOTE_KEEP_YEARLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$REMOTE_KEEP_YEARLY";   fi
      fi

      if [[ "$PRUNE_OPT" == "" ]]; then
        loc_error=1;
        error "No valid prune option, skip prune!";
      else
        export BORG_RSH=${Repo_RSH};
        export BORG_REPO=$Repo_SSH;
        preBorg=${SSHPASS}
      fi
      ;;
    *)
      loc_error=1;
      error "Invalid local/remote value, skip getting repository info! Actual value: $1";
      exit 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg prune ${PRUNE_OPT}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to prune $1 repository: ${BORG_REPO}";
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

  unset BORG_PASSPHRASE;
  unset BORG_RSH;
  unset BORG_REPO;
}

