#!/bin/bash
SVER="v0.0.1"
SDSC="The Next Gen Backup 2"

source $(dirname $0)/classi/functions.sh
source $(dirname $0)/classi/borg_check.sh
source $(dirname $0)/classi/borg_compact.sh
source $(dirname $0)/classi/borg_create.sh
source $(dirname $0)/classi/borg_info.sh
source $(dirname $0)/classi/borg_init.sh
source $(dirname $0)/classi/borg_list.sh
source $(dirname $0)/classi/borg_mount.sh
source $(dirname $0)/classi/borg_prune.sh


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

SSH_OPT=${SSH_OPT:-"-o BatchMode=yes -o StrictHostKeyChecking=accept-new"};

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
  echo "REPO_PASSPHRASE      $REPO_PASSPHRASE";
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
  echo "SSH_PASS             $SSH_PASS";
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
