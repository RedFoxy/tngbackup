#!/bin/bash
# TNGBackup v0.9.0
# License: CC BY-NC 4.0 (Non-Commercial)
# For commercial use, contact: redfoxy@redfoxy.it
# Copyright (c) 2026 RedFoxy Darrest

SVER="0.9.0"
SDSC="The Next Gen Backup - Consolidated"

set -o noglob

############################################################################################################### Batch Mode
batch_mode() {
  local config_dir="$1"
  local script_dir="$(dirname $0)"
  local script_name="$(basename $0)"
  local config_count=0
  local config_success=0
  local config_failed=0
  local batch_start=$(date "+%s")

  if [ ! -d "$config_dir" ]; then
    error "Batch directory does not exist: $config_dir"
    return 1
  fi

  echo "############################################################################"
  echo "INFO: Batch mode started - Processing configs from: $config_dir"
  echo "############################################################################"

  # Process each .conf file in directory
  set +o noglob
  for config_file in "$config_dir"/*.conf; do
    set -o noglob

    if [ ! -f "$config_file" ]; then
      continue
    fi

    ((config_count++))
    local config_basename=$(basename "$config_file")
    echo ""
    echo "INFO: Processing $config_basename"

    local single_start=$(date "+%s")

    # Execute backup script with current config file
    bash "$script_dir/$script_name" "$config_file"
    local result=$?

    local elapsed=$(($(date "+%s") - single_start))

    if [ $result -eq 0 ]; then
      ((config_success++))
      audit_log "batch_process" "SUCCESS" "Completed: $config_basename" "$elapsed"
      echo "INFO: Successfully processed $config_basename (${elapsed}s)"
    else
      ((config_failed++))
      audit_log "batch_process" "FAILED" "Error: $config_basename" "$elapsed"
      echo "WARN: Failed to process $config_basename (${elapsed}s)"
    fi
  done
  set -o noglob

  # Summary
  local batch_end=$(($(date "+%s") - batch_start))
  echo ""
  echo "############################################################################"
  echo "INFO: Batch complete - $config_count files processed, $config_success succeeded, $config_failed failed"
  finished_after $batch_end
  echo "############################################################################"

  if [ $config_success -gt 0 ]; then
    return 0
  else
    return 1
  fi
}

error() {
  echo "$1";
}

if [ ! -n "$REPO_PASSPHRASE" ]; then
  if [ ! -n "$1" ]; then
    error "Please provide the configuration file.";
    exit 1;
  else
    # Check if argument is a directory (batch mode)
    if [ -d "$1" ]; then
      batch_mode "$1"
      exit $?
    fi

    # Local config file provided
    if [ -f $1 ]; then
      . $1
    else
      error $1" file does not exist."
      exit 1;
    fi
  fi
fi

PATH=$PATH:$PATH_OPT

for bin in borg date; do
  if [ -z $(command -v ${bin}) ]; then
    error "Cannot find ${bin}, exiting..."
    exit 1;
  fi
done

DEBUG=${DEBUG:-N};                                      # Attiva il debug
DRYRUN=${DRYRUN:-N};                                    # Solo se debug attivo - Non eseguire i comandi
BACKUP=${BACKUP:-Y};                                    # N = No backup     - Y = Run backup
CHECK=${CHECK:-0};                                      # 0 = No check repo - 1 = Check   before backup - 2 = Check   after backup
PRUNE=${PRUNE:-0};                                      # 0 = No prune      - 1 = Prune   before backup - 2 = Prune   after backup
COMPACT=${COMPACT:-0};                                  # 0 = No compact    - 1 = Compact before backup - 2 = Compact after backup

LOCAL=${LOCAL:-N};                                      # Makes Local backup Yes/No
REMOTE=${REMOTE:-N};                                    # Makes Remote backup Yes/No
LCREATE_REPO=${LCREATE_REPO:-Y};                        # Create Local repository if not exists
LCREATE_REPO_DIR=${LCREATE_REPO_DIR:-Y};                # Create Local repository directory if not exists
RCREATE_REPO=${RCREATE_REPO:-Y};                        # Create Remote repository if not exists
RCREATE_REPO_DIR=${RCREATE_REPO_DIR:-Y};                # Create Remote repository directory if not exists
BORG_ENCRIPTION=${BORG_ENCRIPTION:-"repokey-blake2"};   # Borg encription
SHOWTEXT=${SHOWTEXT:-N}                                 # Show script log
BORG_OPT=${BORG_OPT:-""};                               # Borg common extra options
LOCAL_OPT=${LOCAL_OPT:-""};                             # Borg Local repository extra options
REMOTE_OPT=${REMOTE_OPT:-""};                           # Borg Remote repository extra options

SSH_OPT=${SSH_OPT:-"-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"};

LOCAL_DIR_CHECK=${LOCAL_DIR_CHECK:-"stat --format=%F"}; # Check if local path is a directoy
SSH_DIR_CHECK=${SSH_DIR_CHECK:-"stat --format=%F"};     # Check if remote path is a directoy

Mysql_OPT=${Mysql_OPT:-"--add-drop-database --add-drop-table --add-drop-trigger --add-locks --skip-extended-insert"};

if [ ! -n "$REPO_PASSPHRASE" ]; then error "REPO_PASSPHRASE is not set."; exit 1; fi
if [ ! -n "$BACKUP_PATH" ];     then error "No files or directories to backup are configured."; exit 1; fi

if [[ ! "$SHOWTEXT"            =~ ^[ynYN]$ ]]; then SHOWTEXT="y";         else SHOWTEXT="${SHOWTEXT,,}";                 fi
if [[ ! "$DEBUG"               =~ ^[ynYN]$ ]]; then DEBUG="n";            else DEBUG="${DEBUG,,}";                       fi
if [[ ! "$DRYRUN"              =~ ^[ynYN]$ ]]; then DRYRUN="n";           else DRYRUN="${DRYRUN,,}";                     fi
if [[ ! "$BACKUP"              =~ ^[ynYN]$ ]]; then BACKUP="y";           else BACKUP="${BACKUP,,}";                     fi
if [[ ! $CHECK                 =~ ^[0-2]$ ]];  then CHECK=0;              else CHECK=$CHECK;                             fi
if [[ ! $PRUNE                 =~ ^[0-2]$ ]];  then PRUNE=0;              else PRUNE=$PRUNE;                             fi
if [[ ! $COMPACT               =~ ^[0-2]$ ]];  then COMPACT=0;            else COMPACT=$COMPACT;                         fi

if [[ ! "$LOCAL"               =~ ^[ynYN]$ ]]; then LOCAL="n";            else LOCAL="${LOCAL,,}";                       fi
if [[ ! "$REMOTE"              =~ ^[ynYN]$ ]]; then REMOTE="n";           else REMOTE="${REMOTE,,}";                     fi
if [[ ! "$LCREATE_REPO"        =~ ^[ynYN]$ ]]; then LCREATE_REPO="y";     else LCREATE_REPO="${LCREATE_REPO,,}";         fi
if [[ ! "$LCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then LCREATE_REPO_DIR="y"; else LCREATE_REPO_DIR="${LCREATE_REPO_DIR,,}"; fi
if [[ ! "$RCREATE_REPO"        =~ ^[ynYN]$ ]]; then RCREATE_REPO="y";     else RCREATE_REPO="${RCREATE_REPO,,}";         fi
if [[ ! "$RCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then RCREATE_REPO_DIR="y"; else RCREATE_REPO_DIR="${RCREATE_REPO_DIR,,}"; fi

if [[ $LOCAL != "y"  || ! "$LOCAL_REPO"  ]]; then LOCAL="n"; fi
if [[ $REMOTE != "y" || ! "$REMOTE_REPO" ]]; then REMOTE="n"; fi
if [[ $LOCAL == "n"  && $REMOTE == "n"   ]]; then error "There are no repository, please check LOCAL, LOCAL_REPO, REMOTE, REMOTE_REPO."; exit 1; fi

if [[ ! $LOCAL_KEEP_LAST      =~ ^[0-9]{1,3}$     ]]; then LOCAL_KEEP_LAST=0;     fi
if [[ ! $LOCAL_KEEP_HOURLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_HOURLY=0;   fi
if [[ ! $LOCAL_KEEP_DAILY     =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_DAILY=0;    fi
if [[ ! $LOCAL_KEEP_WEEKLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_WEEKLY=0;   fi
if [[ ! $LOCAL_KEEP_MONTHLY   =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_MONTHLY=0;  fi
if [[ ! $LOCAL_KEEP_YEARLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_YEARLY=0;   fi

if [[ ! $REMOTE_KEEP_LAST     =~ ^[0-9]{1,3}$     ]]; then REMOTE_KEEP_LAST=0;    fi
if [[ ! $REMOTE_KEEP_HOURLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_HOURLY=0;  fi
if [[ ! $REMOTE_KEEP_DAILY    =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_DAILY=0;   fi
if [[ ! $REMOTE_KEEP_WEEKLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_WEEKLY=0;  fi
if [[ ! $REMOTE_KEEP_MONTHLY  =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_MONTHLY=0; fi
if [[ ! $REMOTE_KEEP_YEARLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_YEARLY=0;  fi

if [[ ! $SSH_PORT             =~ ^[0-9]{1,5}$     ]]; then SSH_PORT=22;           else SSH_PORT=$SSH_PORT;               fi

case ${BORG_ENCRIPTION,,} in
  authenticated)
    BORG_ENCRIPTION="authenticated";
    ;;
  authenticated-blake2)
    BORG_ENCRIPTION="authenticated-blake2";
    ;;
  repokey)
    BORG_ENCRIPTION="repokey";
    ;;
  keyfile)
    BORG_ENCRIPTION="keyfile";
    ;;
  repokey-blake2)
    BORG_ENCRIPTION="repokey-blake2";
    ;;
  keyfile-blake2)
    BORG_ENCRIPTION="keyfile-blake2";
    ;;
  *)
    BORG_ENCRIPTION="repokey-blake2";
    ;;
esac

if [ $DEBUG == "y" ]; then
  echo "############################################################################";
  echo "REPOSITORY           $REPOSITORY";
  echo "REPO_PASSPHRASE      $([ -n "$REPO_PASSPHRASE" ] && echo '***REDACTED***' || echo '')";
  echo "CHECK                $CHECK";
  echo "COMPACT              $COMPACT";
  echo "PRUNE                $PRUNE";
  echo "SHOWTEXT             $SHOWTEXT";
  echo "DEBUG                $DEBUG";
  echo "DRYRUN               $DRYRUN";
  echo "BORG_OPT             $BORG_OPT";
  echo "BORG_ENCRIPTION      $BORG_ENCRIPTION";
  echo "Mysql_OPT            $Mysql_OPT";

  echo "--------------------------------------------";
  echo "POSTRUN              $POSTRUN";
  echo "PRERUN               $PRERUN";
  echo "--------------------------------------------";

  echo "SSH_CERT             $SSH_CERT";
  echo "SSH_HOST             $SSH_HOST";
  echo "SSH_PASS             $([ -n "$SSH_PASS" ] && echo '***REDACTED***' || echo '')";
  echo "SSH_PORT             $SSH_PORT";
  echo "SSH_USER             $SSH_USER";
  echo "--------------------------------------------";

  echo "BACKUP               $BACKUP";
  echo "BACKUP_EXCL          $BACKUP_EXCL";
  echo "BACKUP_PATH          $BACKUP_PATH";
  echo "--------------------------------------------";

  echo "LOCAL_REPO           $LOCAL_REPO";
  echo "LCREATE_REPO         $LCREATE_REPO";
  echo "LCREATE_REPO_DIR     $LCREATE_REPO_DIR";
  echo "LOCAL_OPT            $LOCAL_OPT";
  echo -e "\n"

  echo "LOCAL                $LOCAL";
  echo "LOCAL_DIR_CHECK      $LOCAL_DIR_CHECK";
  echo "LOCAL_KEEP_DAILY     $LOCAL_KEEP_DAILY";
  echo "LOCAL_KEEP_HOURLY    $LOCAL_KEEP_HOURLY";
  echo "LOCAL_KEEP_LAST      $LOCAL_KEEP_LAST";
  echo "LOCAL_KEEP_MONTHLY   $LOCAL_KEEP_MONTHLY";
  echo "LOCAL_KEEP_WEEKLY    $LOCAL_KEEP_WEEKLY";
  echo "LOCAL_KEEP_YEARLY    $LOCAL_KEEP_YEARLY";
  echo "--------------------------------------------";

  echo "REMOTE_REPO          $REMOTE_REPO";
  echo "RCREATE_REPO         $RCREATE_REPO";
  echo "RCREATE_REPO_DIR     $RCREATE_REPO_DIR";
  echo "REMOTE_OPT           $REMOTE_OPT";
  echo -e "\n"

  echo "REMOTE               $REMOTE";
  echo "REMOTE_KEEP_DAILY    $REMOTE_KEEP_DAILY";
  echo "REMOTE_KEEP_HOURLY   $REMOTE_KEEP_HOURLY";
  echo "REMOTE_KEEP_LAST     $REMOTE_KEEP_LAST";
  echo "REMOTE_KEEP_MONTHLY  $REMOTE_KEEP_MONTHLY";
  echo "REMOTE_KEEP_WEEKLY   $REMOTE_KEEP_WEEKLY";
  echo "REMOTE_KEEP_YEARLY   $REMOTE_KEEP_YEARLY";
  echo "############################################################################";
fi

if [[ $LOCAL == "n" && $REMOTE == "n" ]]; then
  echo "There are no active repositories.";
  exit 1;
fi

Backup_Start=`date "+%s"`;
Backup_UID=`date "+%Y-%m-%d_%H-%M-%S"`;
Local_SKIP=0;
Remote_SKIP=0;
RUN_ERR=0
RUN_OUT=""

############################################################################################################### Functions

############################################################################################################### Debug
debug() {
  if [ -n "$1" ] && [ $DEBUG == "y" ]; then
    echo -e "$1";
  fi
}

############################################################################################################### Run command
runCMD() {
  if [ -n "$1" ]; then
    RUN_ERR=0; RUN_OUT="";
    debug "\n----------------------------------------------------------------------------\n--- Command: ${1}"
    if [ ! $DRYRUN == "y" ]; then
      RUN_CMD=$1;
      RUN_OUT=$(eval ${RUN_CMD} 2>&1);
      RUN_ERR=$?;
      if [[ $RUN_ERR > 0 ]]; then RUN_ERR=1; fi
      debug "--- Error  : ${RUN_ERR}\n--- Output : \n${RUN_OUT}";
    fi
    debug "----------------------------------------------------------------------------";
  else
    echo "Command not found!";
    exit 127;
  fi
}

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

############################################################################################################### Borg - Compact
borg_compact() {
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
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg compact"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to compact $1 repository: ${BORG_REPO}";
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

############################################################################################################### Borg - Check
borg_check() {
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
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg check --repository-only"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to check $1 repository: ${BORG_REPO}";
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

############################################################################################################### Borg - Init
borg_init() {
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
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg init --encryption=${BORG_ENCRIPTION}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to initialize $1 repository: ${BORG_REPO}";
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

  unset BORG_PASSPHRASE;
  unset BORG_RSH;
  unset BORG_REPO;
}

############################################################################################################### Borg - List
borg_list() {
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
      preBorg=${SSHPASS:-}
      ;;
    *)
      loc_error=1;
      error "Invalid local/remote value, skip list! Actual value: $1";
      exit 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg list ${BORG_REPO}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to list archives from $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "";
    else
      debug "Archives listed from $1 repository";
    fi
  fi

  unset BORG_PASSPHRASE;
  unset BORG_RSH;
  unset BORG_REPO;
}

############################################################################################################### Borg - Mount
borg_mount() {
  local loc_error=0;
  local preBorg="";
  local MOUNT_POINT="";
  export BORG_PASSPHRASE=$REPO_PASSPHRASE;

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
      return 1;
  esac

  if [ $loc_error == 0 ]; then
    runCMD "${preBorg}borg mount ${BORG_REPO} ${MOUNT_POINT}"
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to mount $1 repository: ${BORG_REPO}";
      error "Command: ${RUN_CMD}";
      error "Message: ${RUN_OUT}";
      error "";
      audit_log "mount" "FAILED" "mount failed for $1 repository at ${MOUNT_POINT}" "0"
      return 1;
    else
      debug "Repository mounted successfully for $1 at ${MOUNT_POINT}"
      audit_log "mount" "SUCCESS" "mount completed for $1 repository at ${MOUNT_POINT}" "0"
      return 0;
    fi
  fi
  return 1;
}

############################################################################################################### Borg - Delete
borg_delete() {
  local loc_error=0
  local preBorg=""
  local archive_name=""

  export BORG_PASSPHRASE=$REPO_PASSPHRASE

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case ${1,,} in
      --archive)
        archive_name="$2"
        shift 2
        ;;
      "local"|"remote")
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

  debug "WARNING: About to delete archive '$archive_name' from repository '$BORG_REPO'"
  debug "This is a destructive operation and cannot be undone"

  runCMD "${preBorg}borg delete ${BORG_REPO}::${archive_name}"

  if [ $RUN_ERR -gt 0 ]; then
    error "Failed to delete archive '$archive_name' from repository: ${BORG_REPO}"
    error "Command: ${RUN_CMD}"
    error "Message: ${RUN_OUT}"
    audit_log "delete" "FAILED" "Archive deletion failed: $archive_name" "0"
    return 1
  else
    debug "Archive '$archive_name' deleted successfully from ${BORG_REPO}"
    audit_log "delete" "SUCCESS" "Archive deleted: $archive_name" "0"
    return 0
  fi
}

############################################################################################################### Borg - Extract
borg_extract() {
  local loc_error=0
  local preBorg=""
  local archive_name=""
  local extract_path=""
  local destination_path=""

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

  if [ -z "$destination_path" ]; then
    destination_path="."
  fi

  if [ ! -d "$destination_path" ]; then
    debug "Creating destination directory: $destination_path"
    mkdir -p "$destination_path" || {
      error "Failed to create destination directory: $destination_path"
      audit_log "extract" "FAILED" "Failed to create destination directory" "0"
      return 1
    }
  fi

  local old_pwd=$(pwd)
  cd "$destination_path" || {
    error "Failed to change directory to: $destination_path"
    audit_log "extract" "FAILED" "Failed to change to destination directory" "0"
    cd "$old_pwd"
    return 1
  }

  debug "Extracting '$extract_path' from archive '$archive_name' to directory: $destination_path"

  runCMD "${preBorg}borg extract ${BORG_REPO}::${archive_name} ${extract_path}"

  cd "$old_pwd"

  if [ $RUN_ERR -gt 0 ]; then
    error "Failed to extract '$extract_path' from archive '$archive_name'"
    error "Repository: ${BORG_REPO}"
    error "Command: ${RUN_CMD}"
    error "Message: ${RUN_OUT}"
    audit_log "extract" "FAILED" "Failed to extract: $extract_path from $archive_name" "0"
    return 1
  else
    debug "Successfully extracted '$extract_path' from archive '$archive_name' to: $destination_path"
    audit_log "extract" "SUCCESS" "Extracted: $extract_path from $archive_name" "0"
    return 0
  fi
}

############################################################################################################### Finished after
finished_after() {
  echo -n " - Finished after: ";
  if [ -n "$1" ]; then
    if [ $1 -gt 60 ]; then
      if [ $1 -gt 3600 ]; then
        echo $(date -d@$1 -u +%H:%M:%S);
      else
        echo $(date -d@$1 -u +%M:%S);
      fi
    else
      echo $1" sec";
    fi
  else
    echo "0 sec";
  fi
}

############################################################################################################### Log
log() {
  if [ -n "$1" ]; then
    local text=$1;
    local space=19;

    case ${text,,} in
      -n)
        text="$2"
        printf "#"' %s%*s: '"`date "+%d/%m/%Y %H:%M:%S"`" "$text" "$(($space-${#text}))" "";
        ;;
      -d)
        text="$3"
        printf "#"' %s%*s: '"`date "+%d/%m/%Y %H:%M:%S" --date=@$2`" "$text" "$(($space-${#text}))" "";
        ;;
      *)
        printf "#"' %s%*s: '"${2}"'\n' "$text" "$(($space-${#text}))" "";
        ;;
    esac
  fi
}

############################################################################################################### Audit Log
audit_log() {
  local operation=$1
  local status=$2
  local details=$3
  local duration=${4:-0}

  if [ -z "$AUDIT_LOG_FILE" ]; then
    return 0
  fi

  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$timestamp | $operation | $status | $details | $duration" >> "$AUDIT_LOG_FILE"
}

############################################################################################################### Exclude list
debug "############################################################################ EXCLUDE LIST\n";
debug "Backup exclude: ${BACKUP_EXCL}\n";

IFS=';' read -ra EXCLUDE_LIST <<< "$BACKUP_EXCL"
BORG_EXCLUDE=""
for tmpEXCL in "${EXCLUDE_LIST[@]}"; do
  BORG_EXCLUDE+=" --exclude '$tmpEXCL'"
done
unset tmpEXCL
unset EXCLUDE_LIST

debug "Generated exclude list: ${BORG_EXCLUDE}\n";
############################################################################################################### Pre run Script

if [ ! -z "${PRERUN}" ]; then
  debug "############################################################################ PRE-RUN\n";
  PreRUN_Start=`date "+%s"`;
  runCMD "${PRERUN}"
  ((PreRUN_End=`date "+%s"`-PreRUN_Start));
fi

############################################################################################################### Check backup path

debug "############################################################################ BACKUP PATH\n";
debug "Backup path/files: $BACKUP_PATH\n";

BACKUP_ARR=($(echo "$BACKUP_PATH" | tr ";" "\n")) # There are more than one file/dir to backup?
BORG_PATH=""
BACKUP_NOTEXISTS=""
for tmpPath in "${BACKUP_ARR[@]}"; do
  if [[ -e "$tmpPath" ]]; then                    # Is it exists?
    BORG_PATH+=" $tmpPath"
  else
    BACKUP_NOTEXISTS+=" $tmpPath"
  fi
done
unset tmpPath
unset BACKUP_ARR

debug "Exists backup path/files: ${BORG_PATH}\n";
debug "NOT exists backup path/files: ${BACKUP_NOTEXISTS}\n";

if [ "${BORG_PATH}" == "" ]; then
  error "There are no files or directory to backup! ${BACKUP_PATH}";
  exit 1;
fi

############################################################################################################### Local

if [ $LOCAL == "y" ]; then                        # Backup on local repository?
  debug "############################################################################\nBorg Local Backup";

  if [ -n "${LOCAL_REPO}" ]; then
    if [[ $BACKUP == "y" ]]; then
      if [[ $SHOWTEXT == "y" ]]; then Local_preCheck_Start=`date "+%s"`; fi

      runCMD "mkdir -p $LOCAL_REPO";
      borg_info local
      if [ ! -n "$RUN_OUT" ]; then
        borg_init local
      fi

      if [[ $SHOWTEXT == "y" ]]; then
        ((Local_preCheck_End=`date "+%s"`-Local_preCheck_Start));
      fi
    else
      debug "Local backup skipped";
    fi
  else
    debug "LOCAL_REPO is empty: "${LOCAL_REPO};
    error "Skip local backup...";
    Local_SKIP=1;
  fi
else
  Local_SKIP=1;
fi

############################################################################################################### Remote

if [ $REMOTE == "y" ]; then                       # Backup on remote repository?
  debug "############################################################################\nBorg Remote Backup";

  if [ -n ${REMOTE_REPO} ]; then
    if [[ ! $a == "/*" ]]; then
      REMOTE_REPO="/"${REMOTE_REPO}
    fi
    if [ -n ${SSH_USER} ]; then                   # There is a username? If not exit...
      if [ -n ${SSH_HOST} ]; then                 # There is an hostname? If not exit...
        if [ -n ${SSH_CERT} ]; then               # Must I use a certificate?
          if [ -f "${SSH_CERT}" ]; then           # Is it exist and I can read it?
            if [ -r "${SSH_CERT}" ]; then         # Are you sure that I can read it?
              SSHPASS="";
              SSH_CMD="ssh -p $SSH_PORT -i $SSH_CERT $SSH_USER@$SSH_HOST";
              Repo_RSH="ssh "${SSH_OPT}" -i "${SSH_CERT};
              Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT$REMOTE_REPO";
            else
              error "Certificate not readable!";
              error "Skip remote backup...";
              Remote_SKIP=1;
            fi
          else
            error "Certificate not found!"
            error "Skip remote backup...";
            Remote_SKIP=1;
          fi
        else                                      # Password is the way!
          if [ -n $SSH_PASS ]; then               # Have I a password?
            if [ -z $(command -v sshpass) ]; then
              error "Cannot find sshpass, please install it!"
              error "Skip remote backup...";
              Remote_SKIP=1;
            else
              SSHPASS="sshpass -p ${SSH_PASS} ";
              SSH_CMD="${SSHPASS}ssh -p $SSH_PORT $SSH_USER@$SSH_HOST";
              Repo_RSH="ssh "${SSH_OPT};
              Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT/$REMOTE_REPO";
            fi
          else
            error "SSH Password not provided!";
            error "Skip remote backup...";
            Remote_SKIP=1;
          fi
        fi
      else
        error "SSH Hostname not provided!";
        error "Skip remote backup...";
        Remote_SKIP=1;
      fi
    else
      error "SSH Username not provided!";
      error "Skip remote backup...";
      Remote_SKIP=1;
    fi

    debug "Remote configuration:
    SSHPASS : $SSHPASS
    SSH_CMD : $SSH_CMD
    Repo_RSH: $Repo_RSH
    Repo_SSH: $Repo_SSH
    ";

    if [[ $BACKUP == "y" ]]; then
      if [[ $SHOWTEXT == "y" ]]; then
        Remote_preCheck_Start=`date "+%s"`;
      fi

      if [ $Remote_SKIP == 0 ]; then
        runCMD "$SSH_CMD 'mkdir -p $REMOTE_REPO'";
        borg_info remote
        if [ ! -n "$RUN_OUT" ]; then
          borg_init remote
        fi
      fi

      if [[ $SHOWTEXT == "y" ]]; then
        ((Remote_preCheck_End=`date "+%s"`-Remote_preCheck_Start));
      fi
    else
      debug "Remote backup skipped";
    fi
  else
    debug "REMOTE_REPO is empty: "${REMOTE_REPO};
    error "Skip remote backup...";
    Remote_SKIP=1;
  fi
else
  Remote_SKIP=1;
fi

###############################################################################################################
###############################################################################################################
if [[ $Local_SKIP > 0 ]] && [[ $Remote_SKIP > 0 ]]; then
  echo "Too much errors, unable to run backup."
  exit 1;
fi
###############################################################################################################
###############################################################################################################

if [ $SHOWTEXT == "y" ]; then
  echo "############################################################################";
  log "Backup Unique ID" ${Backup_UID};
  echo "#";
  log "Path to backup" "${BORG_PATH}";
  log "Path not found" ${BACKUP_NOTEXISTS};
  log "Pattern to Exclude" ${BACKUP_EXCL};
  echo "#";
  echo "# Repository:";
  if [ $LOCAL == "y" ]; then
    log "- Local" ${LOCAL_REPO};
  fi
  if [ $REMOTE == "y" ]; then
    log "- Remote" ${REMOTE_REPO};
  fi
  echo "#";
fi

if [ ! -z "${PRERUN}" ]; then
  log -d $PreRUN_Start "Pre-run script";
  finished_after $PreRUN_End
  echo "#";
fi

################### Local

if [ $LOCAL == "y" ] && [ $Local_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then
    echo "# Local:";
    log -d $Local_preCheck_Start "- Config check";
    finished_after $Local_preCheck_End
  fi

  if [[ $CHECK == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Check"; fi
    borg_check local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Prune"; fi
    borg_prune local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Compact"; fi
    borg_compact local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $BACKUP == "y" ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Backup"; fi

   borg_create local

    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Check"; fi
    borg_check local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Prune"; fi
    borg_prune local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Compact"; fi
    borg_compact local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi
fi

###############################################################################################################

if [ $LOCAL == "y" ] && [ $Local_SKIP == 0 ] && [ $REMOTE == "y" ] && [ $Remote_SKIP == 0 ]; then echo "#"; fi

################### Remote

if [ $REMOTE == "y" ] && [ $Remote_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then
    echo "# Remote:";
    log -d $Remote_preCheck_Start "- Config check";
    finished_after $Remote_preCheck_End
  fi

  if [[ $PRUNE == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Prune"; fi
    borg_prune remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Check"; fi
    borg_check remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Compact"; fi
    borg_compact remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $BACKUP == "y" ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Backup"; fi
    borg_create remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Check"; fi
    borg_check remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Prune"; fi
    borg_prune remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "- Compact"; fi
    borg_compact remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi
fi

unset BORG_RSH;
unset BORG_PASSPHRASE;
unset BORG_REPO;

################### Post run Script

if [ ! -z "${POSTRUN}" ]; then
  Step_Start=`date "+%s"`;
  if [ $SHOWTEXT == "y" ]; then
    echo "#";
    log -n "Post-run script"
  fi

  runCMD "${POSTRUN}"

  if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
fi

if [ $SHOWTEXT == "y" ]; then
  echo "#";
  log -n "Backup end";
  ((Backup_End=`date "+%s"`-Backup_Start));
  finished_after $Backup_End;
  echo "############################################################################";
fi
