#!/bin/bash
SVER=0.7.8
SDSC="The Next Gen Backup"

set -o noglob
error() {
  if [ -t 1 ]; then
    echo "$(tput blink; tput setb 4; tput setaf 1; tput bold)$1$(tput sgr0)";
  else
    echo "$1";
  fi
}

if [ ! -n "$REPO_PASSPHRASE" ]; then
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
LCREATE_REPO=${LCREATE_REPO:-Y};                      # Create Local repository if not exists
LCREATE_REPO_DIR=${LCREATE_REPO_DIR:-Y};              # Create Local repository directory if not exists
RCREATE_REPO=${RCREATE_REPO:-Y};                      # Create Remote repository if not exists
RCREATE_REPO_DIR=${RCREATE_REPO_DIR:-Y};              # Create Remote repository directory if not exists
BORG_ENCRIPTION=${BORG_ENCRIPTION:-"repokey-blake2"}; # Borg encription
SHOWTEXT=${SHOWTEXT:-N}                               # Show script log
BORG_OPT=${BORG_OPT:-""};                             # Borg common extra options
LOCAL_OPT=${LOCAL_OPT:-""};                           # Borg Local repository extra options
REMOTE_OPT=${REMOTE_OPT:-""};                         # Borg Remote repository extra options

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
if [[ $LOCAL == "n"  && $REMOTE == "n"   ]]; then error "There are no repository."; exit 1; fi

if [[ ! $LOCAL_KEEP_LAST      =~ ^[0-9]{1,3}$ ]];     then LOCAL_KEEP_LAST=0;     fi
if [[ ! $LOCAL_KEEP_HOURLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_HOURLY=0;  fi
if [[ ! $LOCAL_KEEP_DAILY     =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_DAILY=0;    fi
if [[ ! $LOCAL_KEEP_WEEKLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_WEEKLY=0;   fi
if [[ ! $LOCAL_KEEP_MONTHLY   =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_MONTHLY=0;  fi
if [[ ! $LOCAL_KEEP_YEARLY    =~ ^(-|)[0-9]{1,3}$ ]]; then LOCAL_KEEP_YEARLY=0;   fi

if [[ ! $REMOTE_KEEP_LAST     =~ ^[0-9]{1,3}$ ]];     then REMOTE_KEEP_LAST=0;    fi
if [[ ! $REMOTE_KEEP_HOURLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_HOURLY=0;  fi
if [[ ! $REMOTE_KEEP_DAILY    =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_DAILY=0;   fi
if [[ ! $REMOTE_KEEP_WEEKLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_WEEKLY=0;  fi
if [[ ! $REMOTE_KEEP_MONTHLY  =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_MONTHLY=0; fi
if [[ ! $REMOTE_KEEP_YEARLY   =~ ^(-|)[0-9]{1,3}$ ]]; then REMOTE_KEEP_YEARLY=0;  fi

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

borg_prune() {
  if [ "$1" == "local" ]; then
    PRUNE_OPT=""
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
      error "No valid prune option, skip prune!";
    else
      export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "borg prune ${PRUNE_OPT} ${LOCAL_REPO}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to prune repository: "${LOCAL_REPO};
      fi
    fi
  else
    if [ "$1" == "remote" ]; then
      PRUNE_OPT=""
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
        error "No valid prune option, skip prune!";
      else
        export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
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

borg_compact() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$REPO_PASSPHRASE; unset BORG_RSH;
    runCMD "borg compact ${LOCAL_REPO}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to compact repository: "${LOCAL_REPO};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
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

borg_check() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$REPO_PASSPHRASE; unset BORG_RSH;
    runCMD "borg check --repository-only ${LOCAL_REPO}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to check repository: "${LOCAL_REPO};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
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

borg_info() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$REPO_PASSPHRASE; unset BORG_RSH;
    runCMD "borg info ${LOCAL_REPO}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to get info from repository: "${LOCAL_REPO};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "${SSHPASS}borg info ${Repo_SSH}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to get info from repository: "${Repo_SSH};
      fi
    else
      error "Invalid check value, skip getting info!";
    fi
  fi
}

borg_init() {
  if [ "$1" == "local" ]; then
    export BORG_PASSPHRASE=$REPO_PASSPHRASE; unset BORG_RSH;
    runCMD "borg init --encryption=${BORG_ENCRIPTION} ${LOCAL_REPO}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then
      error "Failed to initialize repository: "${LOCAL_REPO};
    fi
  else
    if [ "$1" == "remote" ]; then
      export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "${SSHPASS}borg init --encryption=${BORG_ENCRIPTION} ${Repo_SSH}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        error "Failed to initialize repository: "${Repo_SSH};
      fi
    else
      error "Invalid check value, skip initialize repository!";
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

########################################################################################################################################### Exclude list
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
########################################################################################################################################### Pre run Script

if [ ! -z "${PRERUN}" ]; then
  debug "############################################################################ PRE-RUN\n";
  PreRUN_Start=`date "+%s"`;
  runCMD "${PRERUN}"
  ((PreRUN_End=`date "+%s"`-PreRUN_Start));
fi

########################################################################################################################################### Check backup path

debug "############################################################################ BACKUP PATH\n";
debug "Backup path/files: $BACKUP_PATH\n";

BACKUP_ARR=($(echo "$BACKUP_PATH" | tr ";" "\n")) # There are more than one file/dir to backup?
BORG_PATH=""
BACKUP_NOTEXISTS=""
for tmpPath in "${BACKUP_ARR[@]}"; do
  if [[ -e "$tmpPath" ]]; then                     # Is it exists?
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

########################################################################################################################################### Local

if [ $LOCAL == "y" ]; then                                              # Backup on local repository?
  debug "############################################################################\nBorg Local Backup";

  if [ -n "${LOCAL_REPO}" ]; then
    if [[ $BACKUP == "y" ]]; then
      if [[ $SHOWTEXT == "y" ]]; then Local_preCheck_Start=`date "+%s"`; fi

      runCMD "$LOCAL_DIR_CHECK $LOCAL_REPO";                              # Directory is it exists?
      if [ $RUN_ERR -gt 0 ]; then                                         # Error, directory maybe it not exists!
        if [ $LCREATE_REPO  == "y" ]; then                                # Must I create the repository?
          if [ $LCREATE_REPO_DIR  == "y" ]; then                          # If not exist must I create it?
            runCMD "mkdir -p $LOCAL_REPO";                                # Create it!
            if [ $RUN_ERR -gt 0 ]; then                                   # Failed to create it...
              error "Failed to create directory: "${LOCAL_REPO};
              error "Skip local backup...";
              Local_SKIP=1;
            else
              borg_init local
              if [ $RUN_ERR -gt 0 ]; then                                 # Fail to create repository, I quit...
                error "Failed to create repository: "${LOCAL_REPO};
                error "Skip local backup...";
                Local_SKIP=1;
              fi
            fi
          else                                                            # Must I not create it? So I quit....
            error 'Directory "'${LOCAL_REPO}'" does not exists.';
            error "Skip local backup...";
            Local_SKIP=1;
          fi
        else
          error 'Repository "'${LOCAL_REPO}'" does not exists.';
          error "Skip local backup...";
          Local_SKIP=1;
        fi
      else                                                                # It exists but isn't a directory or a symbolic link to a directory
        if [[ "${RUN_OUT,,}" != "directory" ]] && [[ "${RUN_OUT,,}" != "symbolic link" ]]; then
          error ${LOCAL_REPO}" already exists but it isn't a directory.";
          error "Skip local backup...";
          Local_SKIP=1;
        else                                                              # Directory exists
          runCMD "ls -A $LOCAL_REPO";
          if [ $RUN_ERR -gt 0 ]; then
            error "Failed to read directory: "${LOCAL_REPO};
            error "Skip local backup...";
            Local_SKIP=1;
          else
            if [ ! -n "$RUN_OUT" ]; then                              # Directory is empty!
              borg_init local
              if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository
                error "Failed to create repository: "${LOCAL_REPO};
                error "Skip local backup...";
                Local_SKIP=1;
              fi
            else                                                      # Directory is not empty, is it a valid repository?
              borg_info local
              if [ $RUN_ERR -gt 0 ]; then                             # Repository not valid, I quit...
                error "Directory is not empty and it isn't a valid repository: "${LOCAL_REPO};
                error "Skip local backup...";
                Local_SKIP=1;
              fi
            fi
          fi
        fi
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

########################################################################################################################################### Remote

if [ $REMOTE == "y" ]; then                                             # Backup on remote repository?
  debug "############################################################################\nBorg Remote Backup";

  if [ -n "${REMOTE_REPO}" ]; then
    if [ -n $SSH_USER ]; then                 # There is a username? If not exit...
      if [ -n $SSH_HOST ]; then               # There is an hostname? If not exit...
        if [ -n $SSH_CERT ]; then             # Must I use a certificate?
          if [ -f "${SSH_CERT}" ]; then       # Is it exist and I can read it?
            if [ -r "${SSH_CERT}" ]; then     # Are you sure that I can read it?
              SSHPASS="";
              SSH_CMD="ssh -p $SSH_PORT -i $SSH_CERT $SSH_USER@$SSH_HOST";
              Repo_RSH='ssh -oBatchMode=yes -i '"${SSH_CERT}";
              Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT/$REMOTE_REPO";
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
        else                                  # Password is the way!
          if [ -n $SSH_PASS ]; then           # Have I a password?
            if [ -z $(command -v sshpass) ]; then
              error "Cannot find sshpass, please install it!"
              error "Skip remote backup...";
              Remote_SKIP=1;
            else
              SSHPASS="sshpass -p ${SSH_PASS} ";
              SSH_CMD="${SSHPASS}ssh -p $SSH_PORT $SSH_USER@$SSH_HOST";
              Repo_RSH="ssh -oBatchMode=yes";
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
        runCMD "$SSH_CMD '$SSH_DIR_CHECK $REMOTE_REPO'";                # Directory is it exists?
        if [ $RUN_ERR -gt 0 ]; then                                     # Error, directory maybe it not exists!
          if [ $RCREATE_REPO  == "y" ]; then                            # Must I create the repository?
            if [ $RCREATE_REPO_DIR  == "y" ]; then                      # If not exist must I create it?
              runCMD "$SSH_CMD 'mkdir -p $REMOTE_REPO'";                # Create it!
              if [ $RUN_ERR -gt 0 ]; then                               # Failed to create it...
                error "Failed to create remote directory: "${REMOTE_REPO};
                error "Skip remote backup...";
                Remote_SKIP=1;
              else
                borg_init remote
                if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository, I quit...
                  error "Failed to create remote repository: "${REMOTE_REPO};
                  error "Skip remote backup...";
                  Remote_SKIP=1;
                fi
              fi
            else                                                        # Must I not create it? So I quit....
              error 'Remote directory "'${REMOTE_REPO}'" does not exists.';
              error "Skip remote backup...";
              Remote_SKIP=1;
            fi
          else
            error 'Remote repository "'${REMOTE_REPO}'" does not exists.';
            error "Skip remote backup...";
            Remote_SKIP=1;
          fi
        else                                                            # It exists but isn't a directory or a symbolic link to a directory
          if [[ "${RUN_OUT,,}" != "directory" ]] && [[ "${RUN_OUT,,}" != "symbolic link" ]]; then
            error ${REMOTE_REPO}" already exists but it isn't a directory.";
            error "Skip remote backup...";
            Remote_SKIP=1;
          else                                                          # Directory exists
            runCMD "$SSH_CMD 'ls -A $REMOTE_REPO'";
            if [ $RUN_ERR -gt 0 ]; then
              error "Failed to read remote directory: "${REMOTE_REPO};
              error "Skip remote backup...";
              Remote_SKIP=1;
            else
              if [ ! -n "$RUN_OUT" ]; then                              # Directory is empty!
                borg_init remote
                if [ $RUN_ERR -gt 0 ]; then                             # Fail to create repository
                  error "Failed to create remote repository: "${REMOTE_REPO};
                  error "Skip remote backup...";
                  Remote_SKIP=1;
                fi
              else                                                      # Directory is not empty, is it a valid repository?
                borg_info remote
                if [ $RUN_ERR -gt 0 ]; then                             # Repository not valid, I quit...
                  error "Remote directory is not empty and it isn't a valid repository: "${REMOTE_REPO};
                  error "Skip remote backup...";
                  Remote_SKIP=1;
                fi
              fi
            fi
          fi
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

    export BORG_PASSPHRASE=$REPO_PASSPHRASE; unset BORG_RSH;
    runCMD "borg create ${BORG_OPT} ${LOCAL_OPT} ${BORG_EXCLUDE} ${LOCAL_REPO}::${Backup_UID} ${BORG_PATH}"
    unset BORG_PASSPHRASE;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${LOCAL_REPO};
      echo "Message: ${RUN_OUT}";
      exit 1;
    fi

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

###########################################################################################################################################

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

    export BORG_PASSPHRASE=$REPO_PASSPHRASE; export BORG_RSH=$Repo_RSH;
    runCMD "${SSHPASS}borg create ${BORG_OPT} ${REMOTE_OPT} ${BORG_EXCLUDE} ${Repo_SSH}::${Backup_UID} ${BORG_PATH}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${REMOTE_REPO};
      echo "Message: ${RUN_OUT}";
      exit 1;
    fi

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

unset BORG_RSH
unset BORG_PASSPHRASE

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