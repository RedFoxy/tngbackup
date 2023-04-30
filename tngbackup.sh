#!/bin/bash
SVER=0.3.2
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

SSH_DIR_CHECK="stat -x"            # *BSD
#SSH_DIR_CHECK="stat --format=%F"  # Linux

DEBUG=${DEBUG:-N};                                    # Attiva il debug
DRYRUN=${DRYRUN:-N};                                  # Solo se debug attivo - Non eseguire i comandi
CHECK=${Check:-1};                                    # 0 = No check repo - 1 = Check & Backup - 2 = Check only
PRUNE=${Prune:-0};                                    # 0 = No prune - 1 = Prune before backup - 2 = Prune after backup

Local=${Local:-N};                                    # Makes Local backup Yes/No
Remote=${Remote:-N};                                  # Makes Remote backup Yes/No
LCREATE_REPO=${LCREATE_REPO:-N};                      # Create Local repository if not exists
LCREATE_REPO_DIR=${LCREATE_REPO_DIR:-N};              # Create Local repository directory if not exists
RCREATE_REPO=${RCREATE_REPO:-N};                      # Create Remote repository if not exists
RCREATE_REPO_DIR=${RCREATE_REPO_DIR:-N};              # Create Remote repository directory if not exists
BORG_ENCRIPTION=${BORG_ENCRIPTION:-"repokey-blake2"}; # Borg encription
SHOWTEXT=${SHOWTEXT:-N}                               # Show script log
Borg_OPT=${Borg_OPT:-""};                             # Borg common extra options
Local_OPT=${Local_OPT:-""};                           # Borg Local repository extra options
Remote_OPT=${Remote_OPT:-""};                         # Borg Remote repository extra options

Mysql_OPT=${Mysql_OPT:-"--add-drop-database --add-drop-table --add-drop-trigger --add-locks --skip-extended-insert"};

if [ ! -n "$Repo_PASSPHRASE" ]; then echo "Repo_PASSPHRASE is not set.";  exit 1; fi

if [[ ! "$DEBUG"               =~ ^[ynYN]$ ]]; then DEBUG="n";            else DEBUG="${DEBUG,,}";                       fi
if [[ ! "$DRYRUN"              =~ ^[ynYN]$ ]]; then DRYRUN="n";           else DRYRUN="${DRYRUN,,}";                     fi
if [[ ! "$CHECK"               =~ ^[0-2]$ ]];  then CHECK="1";            else CHECK=$CHECK;                             fi
if [[ ! "$PRUNE"               =~ ^[0-2]$ ]];  then PRUNE="0";            else PRUNE=$PRUNE;                             fi

if [[ ! "$Local"               =~ ^[ynYN]$ ]]; then Local="n";            else Local="${Local,,}";                       fi
if [[ ! "$Remote"              =~ ^[ynYN]$ ]]; then Remote="n";           else Remote="${Remote,,}";                     fi
if [[ ! "$LCREATE_REPO"        =~ ^[ynYN]$ ]]; then LCREATE_REPO="n";     else LCREATE_REPO="${LCREATE_REPO,,}";         fi
if [[ ! "$LCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then LCREATE_REPO_DIR="n"; else LCREATE_REPO_DIR="${LCREATE_REPO_DIR,,}"; fi
if [[ ! "$RCREATE_REPO"        =~ ^[ynYN]$ ]]; then RCREATE_REPO="n";     else RCREATE_REPO="${RCREATE_REPO,,}";         fi
if [[ ! "$RCREATE_REPO_DIR"    =~ ^[ynYN]$ ]]; then RCREATE_REPO_DIR="n"; else RCREATE_REPO_DIR="${RCREATE_REPO_DIR,,}"; fi
if [[ ! "$SHOWTEXT"            =~ ^[ynYN]$ ]]; then SHOWTEXT="n";         else SHOWTEXT="${SHOWTEXT,,}";                 fi

if [[ ! "$Local_keep_last"     =~ ^[0-9]{1,3}$ ]];     then Local_keep_last="";     fi
if [[ ! "$Local_keep_daily"    =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_daily="";    fi
if [[ ! "$Local_keep_weekly"   =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_weekly="";   fi
if [[ ! "$Local_keep_monthly"  =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_monthly="";  fi
if [[ ! "$Local_keep_yearly"   =~ ^(-|)[0-9]{1,3}$ ]]; then Local_keep_yearly="";   fi

if [[ ! "$Remote_keep_last"    =~ ^[0-9]{1,3}$ ]];     then Remote_keep_last="";    fi
if [[ ! "$Remote_keep_hourly"  =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_hourly="";  fi
if [[ ! "$Remote_keep_daily"   =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_daily="";   fi
if [[ ! "$Remote_keep_weekly"  =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_weekly="";  fi
if [[ ! "$Remote_keep_monthly" =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_monthly=""; fi
if [[ ! "$Remote_keep_yearly"  =~ ^(-|)[0-9]{1,3}$ ]]; then Remote_keep_yearly="";  fi

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

if [[ $Local == "n" && $Remote == "n" ]]; then
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

prune_backup() {
  echo Sucati un pruno $1
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

genExcl() {
  if [ -n "$1" ]; then
    Exclude="$1";
    if [ -n "${Exclude}" ]; then
      Exclude=${Exclude// /\\ };
      echo "--exclude "${Exclude//;/\ --exclude };
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

########################################################################################################################################### Debug

debug "############################################################################
Repo_PASSPHRASE    : $Repo_PASSPHRASE

DEBUG              : ${DEBUG}
DRYRUN             : ${DRYRUN}

Local              : ${Local}
Local_Repo         : ${Local_Repo}
Local_Back         : ${Local_Back}
Local_Excl         : ${Local_Excl}
Local_OPT          : ${Local_OPT}
Local_keep_last    : ${Local_keep_last}
Local_keep_hourly  : ${Local_keep_hourly}
Local_keep_daily   : ${Local_keep_daily}
Local_keep_weekly  : ${Local_keep_weekly}
Local_keep_monthly : ${Local_keep_monthly}
Local_keep_yearly  : ${Local_keep_yearly}

Remote             : ${Remote}
Remote_Repo        : ${Remote_Repo}
Remote_Back        : ${Remote_Back}
Remote_Excl        : ${Remote_Excl}
Remote_OPT         : ${Remote_OPT}
Remote_keep_last   : ${Remote_keep_last}
Remote_keep_hourly : ${Remote_keep_hourly}
Remote_keep_daily  : ${Remote_keep_daily}
Remote_keep_weekly : ${Remote_keep_weekly}
Remote_keep_monthly: ${Remote_keep_monthly}
Remote_keep_yearly : ${Remote_keep_yearly}

SSH_USER           : ${SSH_USER}
SSH_PASS           : ${SSH_PASS}
SSH_HOST           : ${SSH_HOST}
SSH_PORT           : ${SSH_PORT}
SSH_PATH           : ${SSH_PATH}
SSH_CERT           : ${SSH_CERT}

PRERUN             : ${PRERUN}
POSTRUN            : ${POSTRUN}

LCREATE_REPO       : ${LCREATE_REPO}
LCREATE_REPO_DIR   : ${LCREATE_REPO_DIR}
RCREATE_REPO       : ${RCREATE_REPO}
RCREATE_REPO_DIR   : ${RCREATE_REPO_DIR}
BORG_ENCRIPTION    : ${BORG_ENCRIPTION}
Borg_OPT           : ${Borg_OPT}
SHOWTEXT           : ${SHOWTEXT}
############################################################################
";

########################################################################################################################################### Pre run Script

if [ ! -z "${PRERUN}" ]; then
  Step_Start=`date "+%s"`;
  if [ $SHOWTEXT == "y" ]; then PRERUN_LOG=$(log -n "Pre-run script"); fi
  runCMD "${PRERUN}"
  if [ $SHOWTEXT == "y" ]; then ((Step_End=`date "+%s"`-Step_Start)); PRERUN_LOG=${PRERUN_LOG}$(finished_after $Step_End); fi
fi

########################################################################################################################################### Local

if [ $Local == "y" ]; then                                              # Backup on local repository?
  if [[ $SHOWTEXT == "y" && $CHECK -ge 1 ]]; then
    Local_Check_Start=`date "+%s"`;
    Local_Check="$(log -n "Local Repo Check")";
  fi

  debug "############################################################################\nBorg Local Backup";

  if [ ! -n "${Local_Back}" ]; then                                     # Local path/files variable not set
    error "No files or directories to backup are configured.";
    Local_SKIP=1;
  else
    if [[ ! ${Local_Back} = *" "* ]]; then                              # There are more than one file/dir to backup?
      if [[ ! -d "${Local_Back}" ]] && [[ ! -f "${Local_Back}" ]]; then # If not check if it exists
        error ${Local_Back}" not found!";
        Local_SKIP=1;
      fi
    fi
  fi

  # A repository already exists at
  if [ $Local_SKIP == 0 ]; then
    if [ -d "${Local_Repo}" ]; then                                     # Is it a directory?
      if [[ $CHECK -ge 1 ]]; then
        export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
        runCMD "borg check --repository-only ${Local_Repo}";
        unset BORG_PASSPHRASE;
        if [ $RUN_ERR -gt 0 ]; then
          if [ $LCREATE_REPO == "y" ]; then                             # It not exist so create local repository!
            export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
            runCMD "borg init --encryption=${BORG_ENCRIPTION} ${Local_Repo}";
            unset BORG_PASSPHRASE;
            if [ $RUN_ERR -gt 0 ]; then
              error "Failed to create repository: "${Local_Repo};
              Local_SKIP=1;
            fi
          else
            error 'Repository "'${Local_Repo}'" does not exists.';
            Local_SKIP=1;
          fi
        fi
      fi
    else
      if [ -f "${Local_Repo}" ]; then                                   # It's not a directory and it's file!
        error ${Local_Repo}" already exists but it isn't a directory.";
        Local_SKIP=1;
      fi

      if [ $Local_SKIP == 0 ]; then
        if [ $LCREATE_REPO_DIR == "y" ]; then                             # Must create the directory?
          runCMD "mkdir -p ${Local_Repo}"
          if [ $RUN_ERR -gt 0 ]; then             # Failed to create the directory!
            error "Failed to create directory: "${Local_Repo};
            Local_SKIP=1;
          fi

          if [ $Local_SKIP == 0 ]; then
            export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH
            runCMD "borg init --encryption=${BORG_ENCRIPTION} ${Local_Repo}"
            unset BORG_PASSPHRASE;
            if [ $RUN_ERR -gt 0 ]; then # Create repository
              echo "Failed to create repository: "${Local_Repo};
              Local_SKIP=1;
            fi
          fi
        else
          error 'Directory "'${Local_Repo}'" does not exists.';
          Local_SKIP=1;
        fi
      fi
    fi
  fi

  if [ $Local_SKIP == 0 ]; then
    Local_Excl=$(genExcl "${Local_Excl}")
    debug "Local exclude: ${Local_Excl}\n############################################################################\n";
  fi

  if [[ $SHOWTEXT == "y" && $CHECK -ge 1 ]]; then
    ((Local_Check_End=`date "+%s"`-Local_Check_Start));
    Local_Check=$Local_Check$(finished_after $Local_Check_End;);
  fi

  if [[ $Local_SKIP == 0  && $PRUNE == 1 ]]; then
    prune_backup local
  fi
else
  Local_SKIP=1;
fi

########################################################################################################################################### Remote

if [ $Remote == "y" ]; then                                             # Backup on remote repository?
  if [[ $SHOWTEXT == "y" && $CHECK -ge 1 ]]; then
    Remote_Check_Start=`date "+%s"`;
    Remote_Check=$(log -n "Remote Repo Check");
  fi

  debug "############################################################################\nBorg Remote Backup";

  if [ ! -n "${Remote_Back}" ]; then                                    # Remote path/files variable not set
    error "No files or directories to backup are configured.";
    Remote_SKIP=1;
  else
    if [[ ! ${Remote_Back} = *" "* ]]; then                             # There are more than one file/dir to backup?
      if [ ! -d "${Remote_Back}" ] && [ ! -f "${Remote_Back}" ]; then   # is it exists?
        error ${Remote_Back}" not found!";
        Remote_SKIP=1;
      fi
    fi
  fi

  if [ -n $SSH_USER ]; then
    if [ -n $SSH_HOST ]; then
      SSH_PORT=${SSH_PORT:-22}
      if [ -n $SSH_CERT ]; then
        if [ -f "${SSH_CERT}" ]; then
          if [ -r "${SSH_CERT}" ]; then
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
      else
        if [ -n $SSH_PASS ]; then
          if [ -z $(command -v sshpass) ]; then
            error "Cannot find sshpass!"
            Remote_SKIP=1;
          else
            SSHPASS="sshpass -p ${SSH_PASS} ";
            SSH_CMD="${SSHPASS}ssh -p $SSH_PORT $SSH_USER@$SSH_HOST";
            Repo_RSH="ssh -oBatchMode=yes";
            Repo_SSH="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT/$Remote_Repo";
          fi
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

  if [ $Remote_SKIP == 0 ]; then
    if [[ $CHECK -ge 1 ]]; then
      export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
      runCMD "${SSHPASS}borg check --repository-only ${Repo_SSH}"
      unset BORG_PASSPHRASE; unset BORG_RSH;
      if [ $RUN_ERR -gt 0 ]; then
        if [ $RCREATE_REPO == "y" ]; then                                 # Create remote repository?
          runCMD "$SSH_CMD '$SSH_DIR_CHECK $Remote_Repo'";                          # is it exists?
          if [ $RUN_ERR -gt 0 ]; then
            if [ $RCREATE_REPO_DIR  == "y" ]; then                           # If not exist must I create it?
              runCMD "$SSH_CMD 'mkdir -p $Remote_Repo'";
              if [ $RUN_ERR -gt 0 ]; then
                error "Failed to create directory: "${Remote_Repo};
                Remote_SKIP=1;
              fi
            else
              error 'Directory "'${Remote_Repo}'" does not exists.';
              Remote_SKIP=1;
            fi
          else
            if [[ ! "${RUN_OUT,,}" == *" filetype: directory"*  ]]; then
              error ${Remote_Repo}" already exists but it isn't a directory.";
              Remote_SKIP=1;
            fi
          fi

          if [ $Remote_SKIP == 0 ]; then
            export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
            runCMD "${SSHPASS}borg init --encryption=${BORG_ENCRIPTION} ${Repo_SSH}"
            unset BORG_PASSPHRASE; unset BORG_RSH;
            if [ $RUN_ERR -gt 0 ]; then                                     # Fail to create repository
              error "Failed to create repository: "${Remote_Repo};
              Remote_SKIP=1;
            fi
          fi
        else
          error 'Repository "'${Remote_Repo}'" does not exists.';
          Remote_SKIP=1;
        fi
      fi
    fi
  fi

  if [ $Remote_SKIP == 0 ]; then
    Remote_Excl=$(genExcl "${Remote_Excl}")
    debug "Remote Exclude: ${Remote_Excl}\n############################################################################\n";
  fi

  if [[ $SHOWTEXT == "y" && $CHECK -ge 1 ]]; then
    ((Remote_Check_End=`date "+%s"`-Remote_Check_Start));
    Remote_Check=$Remote_Check$(finished_after $Remote_Check_End;);
  fi

  if [[ $Remote_SKIP == 0  && $PRUNE == 1 ]]; then
    prune_backup remote
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

if [ $SHOWTEXT == "y" ]; then
  echo "############################################################################";
  log "Repository" ${Repository};
  log "Unique id" ${Backup_UID};
  echo "#";
  if [ $Local == "y" ]; then
      log "Local Backup Repo" ${Local_Repo};
      log "Local Backup Path" ${Local_Back};
  fi
  if [ $Remote == "y" ]; then
      log "Remote Backup Repo" ${Remote_Repo};
      log "Remote Backup Path" ${Remote_Back};
  fi
  echo "#";
fi

if [ -n "${PRERUN_LOG}" ]; then echo $PRERUN_LOG; fi

################### Local

if [ $Local == "y" ] && [ $Local_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then
    if [[ $CHECK -ge 1 ]]; then echo "${Local_Check}"; fi
    if [[ $CHECK -le 1 ]]; then Step_Start=`date "+%s"`; log -n "Local Backup"; fi
  fi

  if [[ $CHECK -le 1 ]]; then
    export BORG_PASSPHRASE=$Repo_PASSPHRASE; unset BORG_RSH;
    runCMD "borg create ${Borg_OPT} ${Local_OPT} ${Local_Repo}::${Backup_UID} ${Local_Back} ${Local_Excl}"
    unset BORG_PASSPHRASE;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${Local_Repo};
      exit 1;
    fi

    if [ $SHOWTEXT == "y" ]; then
      ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End;
    fi
  fi

  if [[ $PRUNE == 2 ]]; then
    prune_backup local
  fi
fi

################### Remote

if [ $Remote == "y" ] && [ $Remote_SKIP == 0 ]; then
  if [ $SHOWTEXT == "y" ]; then
    if [[ $CHECK -ge 1 ]]; then echo "${Remote_Check}"; fi
    if [[ $CHECK -le 1 ]]; then Step_Start=`date "+%s"`; log -n "Remote Backup"; fi
  fi

  if [[ $CHECK -le 1 ]]; then
    export BORG_PASSPHRASE=$Repo_PASSPHRASE; export BORG_RSH=$Repo_RSH;
    runCMD "${SSHPASS}borg create ${Borg_OPT} ${Remote_OPT} ${Repo_SSH}::${Backup_UID} ${Remote_Back} ${Remote_Excl}"
    unset BORG_PASSPHRASE; unset BORG_RSH;
    if [ $RUN_ERR -gt 0 ]; then # Fail to backup repository
      echo "Failed to create backup: "${Remote_Repo};
      exit 1;
    fi

    if [ $SHOWTEXT == "y" ]; then
      ((Step_End=`date "+%s"`-Step_Start)); finished_after $Step_End;
    fi
  fi

  if [ $PRUNE == 2 ]; then
    prune_backup remote
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