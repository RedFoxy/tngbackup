#!/bin/bash

############################################################################################################### Borg - Check
borg_check() {
  local loc_error=0;
  local preBorg="";
  local operation="check"
  local step_start=$(date "+%s")
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

  log "INFO" "Starting repository check for $1..."

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
      return 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg check --repository-only"
    if [ $RUN_ERR -gt 0 ]; then
      local step_end=$(($(date "+%s") - step_start))
      error "Failed to check $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "Skip $1 backup...";
      error "";
      audit_log "$operation" "FAILED" "check failed for $1 repository" "$step_end"

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
      log "INFO" "Repository check completed successfully for $1"
      audit_log "$operation" "SUCCESS" "check completed for $1 repository" "$step_end"
      return 0;
    fi
  fi
  return 1;
}
