#!/bin/bash
SVER="v0.0.1"
SDSC="The Next Gen Backup 2"

source $(dirname $0)/classi/functions.sh
source $(dirname $0)/classi/borg_check.sh
source $(dirname $0)/classi/borg_compact.sh
source $(dirname $0)/classi/borg_create.sh
source $(dirname $0)/classi/borg_delete.sh
source $(dirname $0)/classi/borg_extract.sh
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

DEBUG=${DEBUG:-N};                                    # Attiva il debug
DRYRUN=${DRYRUN:-N};                                  # Solo se debug attivo - Non eseguire i comandi
SHOWTEXT=${SHOWTEXT:-N}                               # Show script log

BACKUP=${BACKUP:-Y};                                  # N = No backup     - Y = Run backup
CHECK=${CHECK:-0};                                    # 0 = No check repo - 1 = Check   before backup - 2 = Check   after backup
PRUNE=${PRUNE:-0};                                    # 0 = No prune      - 1 = Prune   before backup - 2 = Prune   after backup
COMPACT=${COMPACT:-0};                                # 0 = No compact    - 1 = Compact before backup - 2 = Compact after backup

CREATE_REPO=${CREATE_REPO:-Y};                        # Create Local repository if not exists
CREATE_REPO_DIR=${CREATE_REPO_DIR:-Y};                # Create Local repository directory if not exists
BORG_OPT=${BORG_OPT:-""};                             # Borg common extra options
BORG_ENCRIPTION=${BORG_ENCRIPTION:-"repokey-blake2"}; # Borg encription

SSH_OPT=${SSH_OPT:-"-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"};
DIR_CHECK=${DIR_CHECK:-"stat --format=%F"};           # Check if local path is a directoy

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

if [[ ! "$CREATE_REPO"        =~ ^[ynYN]$ ]]; then CREATE_REPO="y";     else CREATE_REPO="${CREATE_REPO,,}";         fi
if [[ ! "$CREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then CREATE_REPO_DIR="y"; else CREATE_REPO_DIR="${CREATE_REPO_DIR,,}"; fi

if [[ ! $KEEP_LAST      =~ ^[0-9]{1,3}$     ]]; then KEEP_LAST=0;     fi
if [[ ! $KEEP_HOURLY    =~ ^(-|)[0-9]{1,3}$ ]]; then KEEP_HOURLY=0;   fi
if [[ ! $KEEP_DAILY     =~ ^(-|)[0-9]{1,3}$ ]]; then KEEP_DAILY=0;    fi
if [[ ! $KEEP_WEEKLY    =~ ^(-|)[0-9]{1,3}$ ]]; then KEEP_WEEKLY=0;   fi
if [[ ! $KEEP_MONTHLY   =~ ^(-|)[0-9]{1,3}$ ]]; then KEEP_MONTHLY=0;  fi
if [[ ! $KEEP_YEARLY    =~ ^(-|)[0-9]{1,3}$ ]]; then KEEP_YEARLY=0;   fi

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

  echo "SSH_HOST             $SSH_HOST";
  echo "SSH_CERT             $SSH_CERT";
  echo "SSH_PASS             $SSH_PASS";
  echo "SSH_PORT             $SSH_PORT";
  echo "SSH_USER             $SSH_USER";
  echo "SSH_OPT              $SSH_OPT";
  echo "--------------------------------------------";

  echo "BACKUP               $BACKUP";
  echo "BACKUP_EXCL          $BACKUP_EXCL";
  echo "BACKUP_PATH          $BACKUP_PATH";
  echo "--------------------------------------------";

  echo "CREATE_REPO          $CREATE_REPO";
  echo "CREATE_REPO_DIR      $CREATE_REPO_DIR";
  echo -e "\n"

  echo "DIR_CHECK            $DIR_CHECK";
  echo "KEEP_DAILY           $KEEP_DAILY";
  echo "KEEP_HOURLY          $KEEP_HOURLY";
  echo "KEEP_LAST            $KEEP_LAST";
  echo "KEEP_MONTHLY         $KEEP_MONTHLY";
  echo "KEEP_WEEKLY          $KEEP_WEEKLY";
  echo "KEEP_YEARLY          $KEEP_YEARLY";
  echo "--------------------------------------------";

  echo -e "\n"
  echo "############################################################################";
fi

Backup_Start=`date "+%s"`;
Backup_UID=`date "+%Y-%m-%d_%H-%M-%S"`;
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

debug "############################################################################\nBorg Local Backup";

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

check_re() {
  SSHPASS=""
  PRESSH=""
  POSTSSH=""

  if [ -n "${SSH_HOST}" ]; then               # There is an hostname? Than it's a remote backup!
    if [ -n "${SSH_USER}" ]; then             # Check if there is an username
      SSH="${SSH_USER}@${SSH_HOST}"

      if [ -n "${SSH_CERT}" ]; then           # There is a certificate
        if [ -f "${SSH_CERT}" ] && [ -r "${SSH_CERT}" ]; then
          echo "Si esiste e lo leggo"
        else
          error "Certificate ${SSH_CERT} not found or not readable!"
          Remote_SKIP=1
        fi
      else                                      # No certificate? Than Password is the way!
        if [ -n $SSH_PASS ]; then               # Have I a password?
          if [ -z $(command -v sshpass) ]; then
            error "Cannot find sshpass, please install it!"
            Remote_SKIP=1
          else
            PRESSH="sshpass -p ${SSH_PASS} "
          fi
        else
          error "SSH Password not provided!"
          Remote_SKIP=1
        fi
      fi
    else
      error "SSH Username not provided!"
      Remote_SKIP=1
    fi

status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 user@host echo ok 2>&1)

ssh -q u284722-sub1@u284722-sub1.your-storagebox.de -p 23 -i /root/.ssh/hetzner_backup exit
root@backup:/opt# echo $?
0
255 -> fail


    SSH_CMD="ssh -p $SSH_PORT  $SSH"
    Repo_RSH="ssh ${SSH_OPT} -i ${SSH_CERT}"
    Repo_SSH="ssh://$SSH:$SSH_PORT$REMOTE_REPO"

    SSHPASS="";
    SSH_CMD="ssh -p $SSH_PORT -i $SSH_CERT $SSH_USER@$SSH_HOST";
    Repo_RSH="ssh "${SSH_OPT}" -i "${SSH_CERT};
    Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT$REMOTE_REPO";

# SSH     -> user@hostname
# PRESSH  -> solo in caso di password
# POSTSSH -> -p $SSH_PORT -i ${SSH_CERT}

    SSH_CMD="${PRESSH}ssh ${POSTSSH} ${SSH}"
    Repo_RSH="ssh ${SSH_OPT}"
    Repo_SSH="ssh://$SSH:$SSH_PORT/$REMOTE_REPO"


    debug "SSH configuration:
    SSHPASS : $SSHPASS
    SSH_CMD : $SSH_CMD
    Repo_RSH: $Repo_RSH
    Repo_SSH: $Repo_SSH
    "

  else
    Solo locale
  fi
}

############################################################################################################### Remote

if [ $REMOTE == "y" ]; then                       # Backup on remote repository?
  debug "############################################################################\nBorg Remote Backup";

  if [ -n ${REMOTE_REPO} ]; then
    if [[ ! $a == "/*" ]]; then
      REMOTE_REPO="/"${REMOTE_REPO}
    fi


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
