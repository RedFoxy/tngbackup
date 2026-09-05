#!/bin/bash

############################################################################################################### Borg - Delete
borg_delete() {
  local loc_error=0
  local preBorg=""
  local archive_name=""
  local start_time=$(date "+%s")

  export BORG_PASSPHRASE=$REPO_PASSPHRASE

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case ${1,,} in
      --archive)
        archive_name="$2"
        shift 2
        ;;
      "local"|"remote")
        # Legacy support for local/remote parameter - use BORG_REPO environment variable
        if [ -z "$BORG_REPO" ]; then
          if [ "${1,,}" == "local" ]; then
            export BORG_REPO=${LOCAL_REPO:-}
            unset BORG_RSH
          elif [ "${1,,}" == "remote" ]; then
            export BORG_RSH=${Repo_RSH:-}
            export BORG_REPO=${Repo_SSH:-}
            preBorg=${SSHPASS:-}
          fi
        fi
        shift
        ;;
      *)
        error "Unknown option: $1"
        loc_error=1
        shift
        ;;
    esac
  done

  # Validate required parameters
  if [ -z "$archive_name" ]; then
    error "Option --archive is required for delete operation"
    audit_log "delete" "FAILED" "Missing required parameter: --archive" "0"
    return 1
  fi

  if [ -z "$BORG_REPO" ]; then
    error "BORG_REPO is not set"
    audit_log "delete" "FAILED" "BORG_REPO not configured" "0"
    return 1
  fi

  if [ $loc_error != 0 ]; then
    audit_log "delete" "FAILED" "Invalid parameters" "0"
    return 1
  fi

  # Warn about destructive operation
  debug "WARNING: About to delete archive '$archive_name' from repository '$BORG_REPO'"
  debug "This is a destructive operation and cannot be undone"

  # Run borg delete command
  runCMD "${preBorg}borg delete ${BORG_REPO}::${archive_name}"

  local end_time=$(date "+%s")
  local duration=$((end_time - start_time))

  if [ $RUN_ERR -gt 0 ]; then
    error "Failed to delete archive '$archive_name' from repository: ${BORG_REPO}"
    error "Command: ${RUN_CMD}"
    error "Message: ${RUN_OUT}"
    audit_log "delete" "FAILED" "Archive deletion failed: $archive_name" "$duration"
    return 1
  else
    debug "Archive '$archive_name' deleted successfully from ${BORG_REPO}"
    audit_log "delete" "SUCCESS" "Archive deleted: $archive_name" "$duration"
    return 0
  fi
}
