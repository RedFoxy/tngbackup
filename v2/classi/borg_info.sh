#!/bin/bash

############################################################################################################### Borg - Info
borg_info() {
  local loc_error=0
  local preBorg=""
  local archive_name=""
  local start_time=$(date "+%s")

  export BORG_PASSPHRASE=$REPO_PASSPHRASE

  # Check if first argument is "local" or "remote" (legacy mode)
  if [[ "${1,,}" == "local" ]] || [[ "${1,,}" == "remote" ]]; then
    # LEGACY MODE: Original behavior for local/remote
    case ${1,,} in
      "local")
        export BORG_REPO=${LOCAL_REPO}
        unset BORG_RSH
        ;;
      "remote")
        export BORG_RSH=${Repo_RSH}
        export BORG_REPO=$Repo_SSH
        ;;
    esac

    if [ $loc_error == 0 ]; then
      runCMD "${preBorg}borg info"
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to get info from $1 repository: ${BORG_REPO}"
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
    # NEW MODE: Parse options (--archive for specific archive info)
    while [[ $# -gt 0 ]]; do
      case ${1,,} in
        --archive)
          archive_name="$2"
          shift 2
          ;;
        *)
          error "Unknown option: $1"
          loc_error=1
          shift
          ;;
      esac
    done

    if [ $loc_error != 0 ]; then
      audit_log "info" "FAILED" "Invalid parameters" "0"
      return 1
    fi

    # Validate BORG_REPO is set
    if [ -z "$BORG_REPO" ]; then
      error "BORG_REPO is not set"
      audit_log "info" "FAILED" "BORG_REPO not configured" "0"
      return 1
    fi

    debug "Retrieving information from repository: $BORG_REPO"

    # Build borg info command
    local INFO_CMD="borg info"
    if [ -n "$archive_name" ]; then
      INFO_CMD="borg info ${BORG_REPO}::${archive_name}"
      debug "Retrieving information for archive: $archive_name"
    fi

    # Run borg info command
    runCMD "${preBorg}${INFO_CMD}"

    local end_time=$(date "+%s")
    local duration=$((end_time - start_time))

    if [ $RUN_ERR -gt 0 ]; then
      if [ -n "$archive_name" ]; then
        error "Failed to get info for archive '$archive_name' from repository: ${BORG_REPO}"
      else
        error "Failed to get info from repository: ${BORG_REPO}"
      fi
      error "Command: ${RUN_CMD}"
      error "Message: ${RUN_OUT}"
      audit_log "info" "FAILED" "Failed to retrieve repository info" "$duration"
      return 1
    else
      if [ -n "$archive_name" ]; then
        debug "Retrieved information for archive '$archive_name' successfully"
        audit_log "info" "SUCCESS" "Retrieved archive info: $archive_name" "$duration"
      else
        debug "Retrieved repository information successfully"
        audit_log "info" "SUCCESS" "Retrieved repository info" "$duration"
      fi
      return 0
    fi
  fi
}
