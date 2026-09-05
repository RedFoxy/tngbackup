#!/bin/bash

############################################################################################################### Borg - Extract
borg_extract() {
  local loc_error=0
  local preBorg=""
  local archive_name=""
  local extract_path=""
  local destination_path=""
  local start_time=$(date "+%s")

  export BORG_PASSPHRASE=$REPO_PASSPHRASE

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case ${1,,} in
      --archive)
        archive_name="$2"
        shift 2
        ;;
      --path)
        extract_path="$2"
        shift 2
        ;;
      --destination)
        destination_path="$2"
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
    error "Option --archive is required for extract operation"
    audit_log "extract" "FAILED" "Missing required parameter: --archive" "0"
    return 1
  fi

  if [ -z "$extract_path" ]; then
    error "Option --path is required for extract operation"
    audit_log "extract" "FAILED" "Missing required parameter: --path" "0"
    return 1
  fi

  if [ -z "$BORG_REPO" ]; then
    error "BORG_REPO is not set"
    audit_log "extract" "FAILED" "BORG_REPO not configured" "0"
    return 1
  fi

  if [ $loc_error != 0 ]; then
    audit_log "extract" "FAILED" "Invalid parameters" "0"
    return 1
  fi

  # Set default destination path if not provided
  if [ -z "$destination_path" ]; then
    destination_path="."
  fi

  # Ensure destination directory exists
  if [ ! -d "$destination_path" ]; then
    debug "Creating destination directory: $destination_path"
    mkdir -p "$destination_path" || {
      error "Failed to create destination directory: $destination_path"
      audit_log "extract" "FAILED" "Failed to create destination directory" "0"
      return 1
    }
  fi

  # Save current working directory and change to destination
  local old_pwd=$(pwd)
  cd "$destination_path" || {
    error "Failed to change directory to: $destination_path"
    audit_log "extract" "FAILED" "Failed to change to destination directory" "0"
    cd "$old_pwd"
    return 1
  }

  debug "Extracting '$extract_path' from archive '$archive_name' to directory: $destination_path"

  # Run borg extract command
  runCMD "${preBorg}borg extract ${BORG_REPO}::${archive_name} ${extract_path}"

  # Restore previous working directory
  cd "$old_pwd"

  local end_time=$(date "+%s")
  local duration=$((end_time - start_time))

  if [ $RUN_ERR -gt 0 ]; then
    error "Failed to extract '$extract_path' from archive '$archive_name'"
    error "Repository: ${BORG_REPO}"
    error "Command: ${RUN_CMD}"
    error "Message: ${RUN_OUT}"
    audit_log "extract" "FAILED" "Failed to extract: $extract_path from $archive_name" "$duration"
    return 1
  else
    debug "Successfully extracted '$extract_path' from archive '$archive_name' to: $destination_path"
    audit_log "extract" "SUCCESS" "Extracted: $extract_path from $archive_name" "$duration"
    return 0
  fi
}
