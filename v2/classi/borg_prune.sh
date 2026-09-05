#!/bin/bash

############################################################################################################### Borg - Prune
borg_prune() {
  local loc_error=0
  local preBorg=""
  local PRUNE_OPT=""
  local keep_last=""
  local keep_hourly=""
  local keep_daily=""
  local keep_weekly=""
  local keep_monthly=""
  local keep_yearly=""
  local start_time=$(date "+%s")

  export BORG_PASSPHRASE=$REPO_PASSPHRASE

  # Check if first argument is "local" or "remote" (legacy mode)
  if [[ "${1,,}" == "local" ]] || [[ "${1,,}" == "remote" ]]; then
    # LEGACY MODE: Original behavior for local/remote
    case ${1,,} in
      "local")
        if [[ $LOCAL_KEEP_LAST > 0 ]]; then
          PRUNE_OPT=" --keep-last=$LOCAL_KEEP_LAST"
        else
          if [[ $LOCAL_KEEP_HOURLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$LOCAL_KEEP_HOURLY";   fi
          if [[ $LOCAL_KEEP_DAILY   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$LOCAL_KEEP_DAILY";     fi
          if [[ $LOCAL_KEEP_WEEKLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$LOCAL_KEEP_WEEKLY";   fi
          if [[ $LOCAL_KEEP_MONTHLY > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$LOCAL_KEEP_MONTHLY"; fi
          if [[ $LOCAL_KEEP_YEARLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$LOCAL_KEEP_YEARLY";   fi
        fi

        if [[ "$PRUNE_OPT" == "" ]]; then
          loc_error=1
          error "No valid prune option, skip prune!"
        else
          export BORG_REPO=${LOCAL_REPO}
          unset BORG_RSH
        fi
        ;;
      "remote")
        if [[ $REMOTE_KEEP_LAST > 0 ]]; then
          PRUNE_OPT=" --keep-last=$REMOTE_KEEP_LAST"
        else
          if [[ $REMOTE_KEEP_HOURLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$REMOTE_KEEP_HOURLY";   fi
          if [[ $REMOTE_KEEP_DAILY   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$REMOTE_KEEP_DAILY";     fi
          if [[ $REMOTE_KEEP_WEEKLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$REMOTE_KEEP_WEEKLY";   fi
          if [[ $REMOTE_KEEP_MONTHLY > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$REMOTE_KEEP_MONTHLY"; fi
          if [[ $REMOTE_KEEP_YEARLY  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$REMOTE_KEEP_YEARLY";   fi
        fi

        if [[ "$PRUNE_OPT" == "" ]]; then
          loc_error=1
          error "No valid prune option, skip prune!"
        else
          export BORG_RSH=${Repo_RSH}
          export BORG_REPO=$Repo_SSH
          preBorg=${SSHPASS}
        fi
        ;;
    esac

    if [ $loc_error == 0 ]; then
      runCMD "${preBorg}borg prune ${PRUNE_OPT}"
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to prune $1 repository: ${BORG_REPO}"
        error "Command: ${RUN_CMD}"
        error "Message: ${RUN_OUT}"
        error "Skip $1 backup..."
        error ""

        case ${1,,} in
          "local")
            Local_SKIP=1
            ;;
          "remote")
            Remote_SKIP=1
            ;;
        esac
      fi
    fi
  else
    # NEW MODE: Parse options (--keep-last, --keep-daily, --keep-weekly, etc.)
    while [[ $# -gt 0 ]]; do
      case ${1,,} in
        --keep-last)
          keep_last="$2"
          shift 2
          ;;
        --keep-hourly)
          keep_hourly="$2"
          shift 2
          ;;
        --keep-daily)
          keep_daily="$2"
          shift 2
          ;;
        --keep-weekly)
          keep_weekly="$2"
          shift 2
          ;;
        --keep-monthly)
          keep_monthly="$2"
          shift 2
          ;;
        --keep-yearly)
          keep_yearly="$2"
          shift 2
          ;;
        *)
          error "Unknown option: $1"
          loc_error=1
          shift
          ;;
      esac
    done

    # Validate that at least one retention option is provided
    if [ -z "$keep_last" ] && [ -z "$keep_hourly" ] && [ -z "$keep_daily" ] && \
       [ -z "$keep_weekly" ] && [ -z "$keep_monthly" ] && [ -z "$keep_yearly" ]; then
      error "At least one retention option is required (--keep-last, --keep-hourly, --keep-daily, --keep-weekly, --keep-monthly, --keep-yearly)"
      audit_log "prune" "FAILED" "Missing retention options" "0"
      return 1
    fi

    if [ $loc_error != 0 ]; then
      audit_log "prune" "FAILED" "Invalid parameters" "0"
      return 1
    fi

    # Validate BORG_REPO is set
    if [ -z "$BORG_REPO" ]; then
      error "BORG_REPO is not set"
      audit_log "prune" "FAILED" "BORG_REPO not configured" "0"
      return 1
    fi

    # Build prune command with provided options
    PRUNE_OPT=""
    [ -n "$keep_last" ] && PRUNE_OPT="$PRUNE_OPT --keep-last=$keep_last"
    [ -n "$keep_hourly" ] && PRUNE_OPT="$PRUNE_OPT --keep-hourly=$keep_hourly"
    [ -n "$keep_daily" ] && PRUNE_OPT="$PRUNE_OPT --keep-daily=$keep_daily"
    [ -n "$keep_weekly" ] && PRUNE_OPT="$PRUNE_OPT --keep-weekly=$keep_weekly"
    [ -n "$keep_monthly" ] && PRUNE_OPT="$PRUNE_OPT --keep-monthly=$keep_monthly"
    [ -n "$keep_yearly" ] && PRUNE_OPT="$PRUNE_OPT --keep-yearly=$keep_yearly"

    debug "Running prune on repository: $BORG_REPO with options: $PRUNE_OPT"

    # Run borg prune command
    runCMD "${preBorg}borg prune ${PRUNE_OPT}"

    local end_time=$(date "+%s")
    local duration=$((end_time - start_time))

    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to prune repository: ${BORG_REPO}"
      error "Command: ${RUN_CMD}"
      error "Message: ${RUN_OUT}"
      audit_log "prune" "FAILED" "Prune operation failed" "$duration"
      return 1
    else
      debug "Repository prune completed successfully"
      audit_log "prune" "SUCCESS" "Prune operation completed" "$duration"
      return 0
    fi
  fi
}

