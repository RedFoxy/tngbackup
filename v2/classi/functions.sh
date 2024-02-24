#!/bin/bash

set -o noglob # Disabilita l'espansione del percorsi/globbing in pratica non considera i caratteri jolly nella shell

############################################################################################################### Functions

############################################################################################################### Debug
error() {
  echo "$1";
}

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
