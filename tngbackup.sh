#!/bin/bash
SVER=0.7.5a
SDSC="The Next Gen Backup"

set -o noglob
error() {
  if [ -t 1 ]; then
    echo "$(tput blink; tput setb 4; tput setaf 1; tput bold)$1$(tput sgr0)";
  else
    echo "$1";
  fi
}

if [ ! -n "$Repo_PASSPHRASE" ]; then
  if [ ! -n "$1" ]; then
    error "Please provide the configuration file.";
    exit 1;
  else
    if [ -f $1 ]; then
      . $1
    else
      error $1" file does not exist."
      exit 1;
    fi
  fi
fi

for bin in borg date; do
  if [ -z $(command -v ${bin}) ]; then
    error "Cannot find ${bin}, exiting..."
    exit 1;
  fi
done

SSH_DIR_CHECK="stat -f '%HT'"       # *BSD
#SSH_DIR_CHECK="stat --format=%F"   # Linux
LOCAL_DIR_CHECK="stat --format=%F"  # Linux


DEBUG=${DEBUG:-N};                                    # Attiva il debug
DRYRUN=${DRYRUN:-N};                                  # Solo se debug attivo - Non eseguire i comandi
BACKUP=${BACKUP:-Y};                                  # N = No backup     - Y = Run backup
CHECK=${CHECK:-0};                                    # 0 = No check repo - 1 = Check   before backup - 2 = Check   after backup
PRUNE=${PRUNE:-0};                                    # 0 = No prune      - 1 = Prune   before backup - 2 = Prune   after backup
COMPACT=${COMPACT:-0};                                # 0 = No compact    - 1 = Compact before backup - 2 = Compact after backup

LOCAL=${LOCAL:-N};                                    # Makes Local backup Yes/No
REMOTE=${REMOTE:-N};                                  # Makes Remote backup Yes/No
LCREATE_REPO=${LCREATE_REPO:-N};                      # Create Local repository if not exists
LCREATE_REPO_DIR=${LCREATE_REPO_DIR:-N};              # Create Local repository directory if not exists
RCREATE_REPO=${RCREATE_REPO:-N};                      # Create Remote repository if not exists
RCREATE_REPO_DIR=${RCREATE_REPO_DIR:-N};              # Create Remote repository directory if not exists
BORG_ENCRIPTION=${BORG_ENCRIPTION:-"repokey-blake2"}; # Borg encription
SHOWTEXT=${SHOWTEXT:-N}                               # Show script log
BORG_OPT=${BORG_OPT:-""};                             # Borg common extra options
LOCAL_OPT=${LOCAL_OPT:-""};                           # Borg Local repository extra options
REMOTE_OPT=${REMOTE_OPT:-""};                         # Borg Remote repository extra options

Mysql_OPT=${Mysql_OPT:-"--add-drop-database --add-drop-table --add-drop-trigger --add-locks --skip-extended-insert"};

if [ ! -n "$Repo_PASSPHRASE" ]; then error "Repo_PASSPHRASE is not set."; exit 1; fi
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
if [[ ! "$LCREATE_REPO"        =~ ^[ynYN]$ ]]; then LCREATE_REPO="n";     else LCREATE_REPO="${LCREATE_REPO,,}";         fi
if [[ ! "$LCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then LCREATE_REPO_DIR="n"; else LCREATE_REPO_DIR="${LCREATE_REPO_DIR,,}"; fi
if [[ ! "$RCREATE_REPO"        =~ ^[ynYN]$ ]]; then RCREATE_REPO="n";     else RCREATE_REPO="${RCREATE_REPO,,}";         fi
if [[ ! "$RCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then RCREATE_REPO_DIR="n"; else RCREATE_REPO_DIR="${RCREATE_REPO_DIR,,}"; fi

if ! [[ ($Local == "y" && ! -z "$Local_Repo") || ($Remote == "y" && ! -z "$Remote_Repo") ]]; then error "There are no repository."; exit 1; fi

if [[ ! $Local_keep_last      =~ ^[0-9]{1,3}$ ]];     then Local_keep_last=0;     fi
if [[ ! $Local_keep_hourly    =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_hourly=0;  fi
if [[ ! $Local_keep_daily     =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_daily=0;    fi
if [[ ! $Local_keep_weekly    =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_weekly=0;   fi
if [[ ! $Local_keep_monthly   =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_monthly=0;  fi
if [[ ! $Local_keep_yearly    =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_yearly=0;   fi

if [[ ! $Remote_keep_last     =~ ^[0-9]{1,3}$ ]];     then Remote_keep_last=0;    fi
if [[ ! $Remote_keep_hourly   =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_hourly=0;  fi
if [[ ! $Remote_keep_daily    =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_daily=0;   fi
if [[ ! $Remote_keep_weekly   =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_weekly=0;  fi
if [[ ! $Remote_keep_monthly  =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_monthly=0; fi
if [[ ! $Remote_keep_yearly   =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_yearly=0;  fi

if [[ ! $SSH_PORT             =~ ^[0-9]{1,5}$ ]];     then SSH_PORT=22;           else SSH_PORT=$SSH_PORT;               fi

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

########################################################################################################################################### Functions

debug() {
  if [ -n "$1" ] && [ $DEBUG == "y" ]; then
    echo -e "$1";
  fi
}

runCMD() {
  if [ -n "$1" ]; then
    RUN_ERR=0; RUN_OUT="";
    debug "\n----------------------------------------------------------------------------\n--- Command: ${1}"
    if [ ! $DRYRUN == "y" ]; then
      RUN_OUT=$(eval ${1} 2>&1);
      RUN_ERR=$?;
      if [[ $RUN_ERR > 0 ]]; then RUN_ERR=1; fi
      debug "--- Error  : ${RUN_ERR}\n--- Output : \n${RUN_OUT}";
    fi
    debug "----------------------------------------------------------------------------";
  else
    echo "No command to run!";
  fi
}

prune_backup() {
  if [ "$1" == "local" ]; then
    PRUNE_OPT=""
    if [[ $Local_keep_last > 0 ]]; then
      PRUNE_OPT=" --keep-last=$Local_keep_last";
    else
      if [[ $Local_keep_hourly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$Local_keep_hourly";   fi
      if [[ $Local_keep_daily   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$Local_keep_daily";     fi
      if [[ $Local_keep_weekly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$Local_keep_weekly";   fi
      if [[ $Local_keep_monthly > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$Local_keep_monthly"; fi
      if [[ $Local_keep_yearly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$Local_keep_yearly";   fi
    fi

    if [[ "$PRUNE_OPT" == "" ]]; then
      error "No valid prune option, skip prune!";
    else
      export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "borg prune ${PRUNE_OPT} ${Local_Repo}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to prune repository: "${Local_Repo};
      fi
    fi
  else
    if [ "$1" == "remote" ]; then
      PRUNE_OPT=""
      if [[ $Remote_keep_last > 0 ]]; then
        PRUNE_OPT=" --keep-last=$Remote_keep_last";
      else
        if [[ $Remote_keep_hourly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-hourly=$Remote_keep_hourly";   fi
        if [[ $Remote_keep_daily   > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-daily=$Remote_keep_daily";     fi
        if [[ $Remote_keep_weekly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-weekly=$Remote_keep_weekly";   fi
        if [[ $Remote_keep_monthly > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-monthly=$Remote_keep_monthly"; fi
        if [[ $Remote_keep_yearly  > 0 ]]; then PRUNE_OPT="$PRUNE_OPT --keep-yearly=$Remote_keep_yearly";   fi
      fi

      if [[ "$PRUNE_OPT" == "" ]]; then
        error "No valid prune option, skip prune!";
      else
        export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
        runCMD "${SSHPASS}borg prune ${PRUNE_OPT} ${Repo_SSH}"
        unset BORG_PASSPHRASE;
        if [ $RUN_ERR -gt 0 ]; then
          error "Failed to prune repository: "${Repo_SSH};
        fi
      fi
    else
      error "Invalid prune value, skip prune!";
    fi
  fi
}

compact_backup() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
    runCMD "borg compact ${Local_Repo}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to compact repository: "${Local_Repo};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "${SSHPASS}borg compact ${Repo_SSH}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to compact repository: "${Repo_SSH};
      fi
    else
      error "Invalid compact value, skip compact!";
    fi
  fi
}

check_backup() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
    runCMD "borg check --repository-only ${Local_Repo}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to check repository: "${Local_Repo};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "${SSHPASS}borg check --repository-only ${Repo_SSH}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to check repository: "${Repo_SSH};
      fi
    else
      error "Invalid check value, skip check!";
    fi
  fi
}

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

log() {
  if [ -n "$1" ]; then
    local text=$1;
    local space=19;

    if [ "$text" == "-n" ]; then
      text="$2"
      printf "#"' %s%*s: '"`date "+%d/%m/%Y %H:%M:%S"`" "$text" "$(($space-${#text}))" "";
    else
      printf "#"' %s%*s: '"${2}"'\n' "$text" "$(($space-${#text}))" "";
    fi
  fi
}

########################################################################################################################################### Exclude list

debug "Backup exclude: ${BACKUP_EXCL}\n############################################################################\n";

IFS=';' read -ra EXCLUDE_LIST <<< "$BACKUP_EXCL"
BACKUP_EXCL=""
for pattern in "${EXCLUDE_LIST[@]}"; do
  BACKUP_EXCL+=" --exclude '$pattern'"
done
unset EXCLUDE_LIST

debug "Generated exclude list: ${BACKUP_EXCL}\n############################################################################\n";

########################################################################################################################################### Pre run Script

if [ ! -z "${PRERUN}" ]; then
  Step_Start=`date "+%s"`;
  if [ $SHOWTEXT == "y" ]; then PRERUN_LOG=$(log -n "Pre-run script"); fi
  runCMD "${PRERUN}"
  if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); PRERUN_LOG=${PRERUN_LOG}$(finished_after $Step_End); fi
fi

########################################################################################################################################### Check path

debug "Backup path/files: $BACKUP_PATH\n";

BACKUP_PATH=($(echo "$BACKUP_PATH" | tr ";" "\n")) # There are more than one file/dir to backup?
BACKUP_PATH=""
BACKUP_NOTEXISTS=""
for tmpPath in "${BACKUP_PATH[@]}"; do
echo file: $tmpPath
  if [[ -e "$tmpPath" ]]; then                     # Is it exists?
    BACKUP_PATH+=" $tmpPath"
  else
    BACKUP_NOTEXISTS+=" $tmpPath"
  fi
done
unset tmpPath

debug "Exists backup path/files: ${BACKUP_PATH}\nNOT exists backup path/files: ${BACKUP_NOTEXISTS}\n############################################################################\n";

if [ "${BACKUP_PATH}" == "" ]; then
  error "There are no files or directory to backup! ${BACKUP_PATH}";
  exit 1;
fi

########################################################################################################################################### Local

if [ $LOCAL == "y" ]; then                                              # Backup on local repository?
  debug "############################################################################\nBorg Local Backup";

  if [ -n "${Local_Repo}" ]; then
    if [[ $BACKUP == "y" ]]; then
      if [[ $SHOWTEXT == "y" ]]; then
        Local_preCheck_Start=`date "+%s"`;
        Local_preCheck="$(log -n "Local Pre-Check run")";
      fi

      runCMD "$LOCAL_DIR_CHECK $Local_Repo'";                             # Directory is it exists?
      if [ $RUN_ERR -gt 0 ]; then                                         # Error, directory maybe it not exists!
        if [ $LCREATE_REPO  == "y" ]; then                                # Must I create the repository?
          if [ $LCREATE_REPO_DIR  == "y" ]; then                          # If not exist must I create it?
            runCMD "mkdir -p $Local_Repo";                                # Create it!
            if [ $RUN_ERR -gt 0 ]; then                                   # Failed to create it...
              error "Failed to create directory: "${Local_Repo};
              Local_SKIP=1;
            else
              export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
              runCMD "borg init --encryption=${BORG_ENCRIPTION} ${Local_Repo}";
              unset BORG_PASSPHRASE;
              if [ $RUN_ERR -gt 0 ]; then                                 # Fail to create repository, I quit...
                error "Failed to create repository: "${Local_Repo};
                Local_SKIP=1;
              fi
            fi
          else                                                            # Must I not create it? So I quit....
            error 'Directory "'${Local_Repo}'" does not exists.';
            Local_SKIP=1;
          fi
        else
          error 'Repository "'${Local_Repo}'" does not exists.';
          Local_SKIP=1;
        fi
      else
        if [[ ! "${RUN_OUT,,}" == "directory"  ]]; then                   # It exists but isn't a directory
          error ${Local_Repo}" already exists but it isn't a directory.";
          Local_SKIP=1;
        else                                                              # Directory exists
          runCMD "ls -A $Local_Repo";
          if [ $RUN_ERR -gt 0 ]; then
            error "Failed to read directory: "${Local_Repo};
            Local_SKIP=1;
          else
            if [ ! -n "$RUN_OUT" ]; then                              # Directory is empty!
              export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
              runCMD "borg init --encryption=${BORG_ENCRIPTION} ${Local_Repo}";
              unset BORG_PASSPHRASE;
              if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository
                error "Failed to create repository: "${Local_Repo};
                Local_SKIP=1;
              fi
            else                                                      # Directory is not empty, is it a valid repository?
              runCMD "borg info ${Local_Repo}"
              if [ $RUN_ERR -gt 0 ]; then                             # Repository not valid, I quit...
                error "Directory is not empty and it isn't a valid repository: "${Local_Repo};
                Local_SKIP=1;
              fi
            fi
          fi
        fi
      fi

      if [[ $SHOWTEXT == "y" ]]; then
        ((Local_preCheck_End=`date "+%s"`-Local_preCheck_Start));
        Local_preCheck=$Local_preCheck$(finished_after $Local_preCheck_End;);
      fi
    else
      debug "Local backup skipped";
    fi
  else
    debug "Local_Repo is empty: "${Local_Repo};
    Local_SKIP=1;
  fi
else
  Local_SKIP=1;
fi

########################################################################################################################################### Remote

if [ $REMOTE == "y" ]; then                                             # Backup on remote repository?
  debug "############################################################################\nBorg Remote Backup";

  if [ -n "${Remote_Repo}" ]; then
    if [ -n $SSH_USER ]; then                 # There is a username? If not exit...
      if [ -n $SSH_HOST ]; then               # There is an hostname? If not exit...
        if [ -n $SSH_CERT ]; then             # Must I use a certificate?
          if [ -f "${SSH_CERT}" ]; then       # Is it exist and I can read it?
            if [ -r "${SSH_CERT}" ]; then     # Are you sure that I can read it?
              SSHPASS="";
              SSH_CMD="ssh -p $SSH_PORT -i $SSH_CERT $SSH_USER@$SSH_HOST";
              Repo_RSH='ssh -oBatchMode=yes -i '"${SSH_CERT}";
              Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT/$Remote_Repo";
            else
              error "Certificate not readable!";
              Remote_SKIP=1;
            fi
          else
            error "Certificate not found!"
            Remote_SKIP=1;
          fi
        else                                  # Password is the way!
          if [ -n $SSH_PASS ]; then           # Have I a password?
            if [ -z $(command -v sshpass) ]; then
              error "Cannot find sshpass, please install it!"
              Remote_SKIP=1;
            else
              SSHPASS="sshpass -p ${SSH_PASS} ";
              SSH_CMD="${SSHPASS}ssh -p $SSH_PORT $SSH_USER@$SSH_HOST";
              Repo_RSH="ssh -oBatchMode=yes";
              Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT/$Remote_Repo";
            fi
          else
            error "Password not provided!";
            Remote_SKIP=1;
          fi
        fi
      else
        error "Hostname not provided!";
        Remote_SKIP=1;
      fi
    else
      error "User name not provided!";
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
        Remote_preCheck=$(log -n "Remote Pre-Check run");
      fi

      if [ $Remote_SKIP == 0 ]; then
        runCMD "$SSH_CMD '$SSH_DIR_CHECK $Remote_Repo'";                # Directory is it exists?
        if [ $RUN_ERR -gt 0 ]; then                                     # Error, directory maybe it not exists!
          if [ $RCREATE_REPO  == "y" ]; then                            # Must I create the repository?
            if [ $RCREATE_REPO_DIR  == "y" ]; then                      # If not exist must I create it?
              runCMD "$SSH_CMD 'mkdir -p $Remote_Repo'";                # Create it!
              if [ $RUN_ERR -gt 0 ]; then                               # Failed to create it...
                error "Failed to create directory: "${Remote_Repo};
                Remote_SKIP=1;
              else
                export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
                runCMD "${SSHPASS}borg init --encryption=${BORG_ENCRIPTION} ${Repo_SSH}"
                unset BORG_PASSPHRASE; unset BORG_RSH;
                if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository, I quit...
                  error "Failed to create repository: "${Remote_Repo};
                  Remote_SKIP=1;
                fi
              fi
            else                                                        # Must I not create it? So I quit....
              error 'Directory "'${Remote_Repo}'" does not exists.';
              Remote_SKIP=1;
            fi
          else
            error 'Repository "'${Remote_Repo}'" does not exists.';
            Remote_SKIP=1;
          fi
        else
          if [[ ! "${RUN_OUT,,}" == "directory"  ]]; then               # It exists but isn't a directory
            error ${Remote_Repo}" already exists but it isn't a directory.";
            Remote_SKIP=1;
          else                                                          # Directory exists
            runCMD "$SSH_CMD 'ls -A $Remote_Repo'";
            if [ $RUN_ERR -gt 0 ]; then
              error "Failed to read directory: "${Remote_Repo};
              Remote_SKIP=1;
            else
              if [ ! -n "$RUN_OUT" ]; then                              # Directory is empty!
                export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
                runCMD "${SSHPASS}borg init --encryption=${BORG_ENCRIPTION} ${Repo_SSH}"
                unset BORG_PASSPHRASE; unset BORG_RSH;
                if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository
                  error "Failed to create repository: "${Remote_Repo};
                  Remote_SKIP=1;
                fi
              else                                                      # Directory is not empty, is it a valid repository?
                export BORG_RSH=$Repo_RSH;
                runCMD "${SSHPASS}borg info ${Repo_SSH}"
                unset BORG_RSH;
                if [ $RUN_ERR -gt 0 ]; then                             # Repository not valid, I quit...
                  error "Directory is not empty and it isn't a valid repository: "${Remote_Repo};
                  Remote_SKIP=1;
                fi
              fi
            fi
          fi
        fi
      fi

      if [[ $SHOWTEXT == "y" ]]; then
        ((Remote_preCheck_End=`date "+%s"`-Remote_preCheck_Start));
        Remote_preCheck=$Remote_preCheck$(finished_after $Remote_preCheck_End;);
      fi
    else
      debug "Remote backup skipped";
    fi
  else
    debug "Remote_Repo is empty: "${Remote_Repo};
    Remote_SKIP=1;
  fi
else
  Remote_SKIP=1;
fi

###########################################################################################################################################
###########################################################################################################################################
if [[ $Local_SKIP > 0 ]] && [[ $Remote_SKIP > 0 ]]; then
  echo "Too much errors, unable to run backup."
  exit 1;
fi
###########################################################################################################################################
###########################################################################################################################################

if [ $SHOWTEXT == "y" ]; then
  echo "############################################################################";
  log "Repository" ${Repository};
  log "Unique id" ${Backup_UID};
  echo "#";
  log "Backup Path" ${BACKUP_PATH};
  log "Backup Exclude" ${BACKUP_EXCL};
  echo "#";
  if [ $LOCAL == "y" ]; then
    log "Local Backup Repo" ${Local_Repo};
  fi
  if [ $REMOTE == "y" ]; then
    log "Remote Backup Repo" ${Remote_Repo};
  fi
  echo "#";
fi

if [ -n "${PRERUN_LOG}" ]; then echo $PRERUN_LOG; fi

################### Local

if [ $LOCAL == "y" ] && [ $Local_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then echo "${Local_preCheck}"; fi

  if [[ $CHECK == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Check"; fi
    check_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Prune"; fi
    prune_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Compact"; fi
    compact_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $BACKUP == "y" ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Backup"; fi

    export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
    runCMD "borg create ${BORG_OPT} ${LOCAL_OPT} ${Local_Repo}::${Backup_UID} ${BACKUP_PATH} ${BACKUP_EXCL}"
    unset BORG_PASSPHRASE;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${Local_Repo};
      exit 1;
    fi

    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Check"; fi
    check_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Prune"; fi
    prune_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Local Compact"; fi
    compact_backup local
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi
fi

###########################################################################################################################################

if [ $LOCAL == "y" ] && [ $Local_SKIP == 0 ] && [ $REMOTE == "y" ] && [ $Remote_SKIP == 0 ]; then echo "#";

################### Remote

if [ $REMOTE == "y" ] && [ $Remote_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then echo "${Remote_preCheck}"; fi

  if [[ $PRUNE == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Prune"; fi
    prune_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Check"; fi
    check_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 1 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Compact"; fi
    compact_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $BACKUP == "y" ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Backup"; fi

    export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
    runCMD "${SSHPASS}borg create ${BORG_OPT} ${REMOTE_OPT} ${Repo_SSH}::${Backup_UID} ${BACKUP_PATH} ${BACKUP_EXCL}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${Remote_Repo};
      exit 1;
    fi

    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $CHECK == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Check"; fi
    check_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $PRUNE == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Prune"; fi
    prune_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi

  if [[ $COMPACT == 2 ]]; then
    if [ $SHOWTEXT == "y" ]; then Step_Start=`date "+%s"`; log -n "Remote Compact"; fi
    compact_backup remote
    if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End; fi
  fi
fi

unset BORG_RSH
unset BORG_PASSPHRASE

################### Post run Script

if [ ! -z "${POSTRUN}" ]; then
  Step_Start=`date "+%s"`;
  if [ $SHOWTEXT == "y" ]; then
    log -n "Post-run script"
  fi

  runCMD "${POSTRUN}"

  if [ $SHOWTEXT == "y" ]; then
    ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End;
  fi
fi

if [ $SHOWTEXT == "y" ]; then
  echo "#";
  log -n "Backup end";
  ((Backup_End=`date "+%s"`-Backup_Start));
  finished_after $Backup_End;
  echo "############################################################################";
fi