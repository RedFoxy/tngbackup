#!/bin/bash
#
# TNGBackup — The Next Generation Borg Backup Management Utility
#
# SCRIPT METADATA
#
SCRIPT_NAME="tngbackup"
SCRIPT_VERSION="2.0.1"
SCRIPT_DESC="The Next Generation Borg Backup management utility"
SCRIPT_AUTHOR="Massimo \"RedFoxy Darrest\" Cicciò"
SCRIPT_LICENSE="CC BY-NC 4.0 (Non-Commercial) + Commercial License"

#
# SECURITY & STRICT MODE
#
set +o history
set -euo pipefail

#
# DEFAULT VARIABLES
#

# Configuration file path (default: user home directory)
TNGB_CONFIG="${TNGB_CONFIG:-$HOME/.config/tngbackup.conf}"

# Output control
DEBUG="${DEBUG:-n}"
DRYRUN="${DRYRUN:-n}"
SHOWTEXT="${SHOWTEXT:-y}"

# Repository configuration
REPO_URI="${REPO_URI:-}"
REPO_PASSPHRASE="${REPO_PASSPHRASE:-}"

# Backup configuration
BACKUP="${BACKUP:-y}"
BACKUP_PATH="${BACKUP_PATH:-}"
BACKUP_EXCLUDE="${BACKUP_EXCLUDE:-}"
ARCHIVE_NAME="${ARCHIVE_NAME:-}"
RESTORE_PATH="${RESTORE_PATH:-}"
MOUNT_PATH="${MOUNT_PATH:-/mnt/borg}"

# Borg options
BORG_ENCRYPTION="${BORG_ENCRYPTION:-repokey-blake2}"
BORG_OPT="${BORG_OPT:-}"
SSH_OPT="${SSH_OPT:--o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5}"
SSH_PORT="${SSH_PORT:-22}"

# Retention policy
KEEP_LAST="${KEEP_LAST:-10}"
KEEP_HOURLY="${KEEP_HOURLY:-}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-12}"
KEEP_YEARLY="${KEEP_YEARLY:-}"

# Logging and state
LOG_FILE="${LOG_FILE:-}"
AUDIT_LOG_FILE="${AUDIT_LOG_FILE:-}"
TEMP_CONFIG="${TEMP_CONFIG:-}"
START_TIME="${START_TIME:-}"
OPERATION="${OPERATION:-}"
OPERATION_STATUS="${OPERATION_STATUS:-}"

# Non-interactive Borg behaviour: never block waiting on a TTY prompt.
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK="${BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK:-yes}"
export BORG_RELOCATED_REPO_ACCESS_IS_OK="${BORG_RELOCATED_REPO_ACCESS_IS_OK:-yes}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

error() {
    echo "[ERROR] $1" >&2
}

debug() {
    if [ "$DEBUG" = "y" ]; then
        echo "[DEBUG] $1"
    fi
}

log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Console output
    if [ "$SHOWTEXT" = "y" ]; then
        case "$level" in
            ERROR)   echo "[$timestamp] [ERROR] $msg" >&2 ;;
            WARN)    echo "[$timestamp] [WARN] $msg" >&2 ;;
            INFO)    echo "[$timestamp] [INFO] $msg" ;;
            DEBUG)   if [ "$DEBUG" = "y" ]; then echo "[$timestamp] [DEBUG] $msg"; fi ;;
        esac
    fi

    # File log (if --log specified). Never abort the run because the log
    # file is not writable (e.g. /var/log without root privileges).
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Pipe Borg output to the log file when one is configured, otherwise to stdout.
# Using `tee -a ""` (the previous behaviour) fails when no log file is set.
tee_log() {
    if [ -n "$LOG_FILE" ]; then
        tee -a "$LOG_FILE"
    else
        cat
    fi
}

# Prepare the Borg environment for the configured repository.
# Sets BORG_PASSPHRASE/BORG_REPO and, for ssh:// URIs, BORG_RSH.
setup_borg_env() {
    export BORG_PASSPHRASE="$REPO_PASSPHRASE"
    export BORG_REPO="$REPO_URI"

    case "$REPO_URI" in
        ssh://*)
            export BORG_RSH="ssh $SSH_OPT -p $SSH_PORT"
            debug "Remote repository detected, BORG_RSH configured"
            ;;
        *)
            unset BORG_RSH 2>/dev/null || true
            ;;
    esac
}

# Execute a Borg command.
# Honours DRYRUN, keeps stdin closed so Borg can never hang on a prompt,
# and mirrors combined output to the log file.
run_borg() {
    debug "Executing: borg $*"

    if [ "$DRYRUN" = "y" ]; then
        log "INFO" "[DRY-RUN] borg $*"
        return 0
    fi

    borg "$@" < /dev/null 2>&1 | tee_log
}

# Common wrapper: run an operation, emit the audit record, set OPERATION_STATUS.
finish_operation() {
    local operation="$1"
    local rc="$2"
    local details="$3"

    # Borg exit code convention: 0 = success, 1 = completed with warnings
    # (e.g. a file could not be read), >=2 = error. A warning must not be
    # reported as a failure: the archive was created.
    if [ "$rc" -eq 0 ]; then
        OPERATION_STATUS="SUCCESS"
        audit_log "$operation" "SUCCESS" "$details" "$(calculate_duration)"
        log "INFO" "$operation completed successfully"
        return 0
    elif [ "$rc" -eq 1 ]; then
        OPERATION_STATUS="WARNING"
        audit_log "$operation" "WARNING" "$details" "$(calculate_duration)"
        log "WARN" "$operation completed with warnings (borg exit 1)"
        return 0
    fi

    OPERATION_STATUS="FAILED"
    audit_log "$operation" "FAILED" "$details" "$(calculate_duration)"
    error "$operation failed (borg exit $rc)"
    return "$rc"
}

# Build the retention arguments from the KEEP_* configuration.
# Echoes the arguments; returns 1 when no retention rule is configured.
build_retention_opts() {
    local opts=()
    local rule name value

    for rule in "last:$KEEP_LAST" "hourly:$KEEP_HOURLY" "daily:$KEEP_DAILY" \
                "weekly:$KEEP_WEEKLY" "monthly:$KEEP_MONTHLY" "yearly:$KEEP_YEARLY"; do
        name="${rule%%:*}"
        value="${rule#*:}"
        if [ -n "$value" ] && [ "$value" != "0" ]; then
            opts+=("--keep-${name}=${value}")
        fi
    done

    if [ "${#opts[@]}" -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${opts[@]}"
    return 0
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

show_help() {
    cat << 'HELPTEXT'
USAGE: tngbackup [OPERATION] [OPTIONS]

OPERATIONS:
  init              Initialize new Borg repository
  backup            Create backup archive
  list              List archives or archive contents
  mount             Mount repository or archive
  check             Verify repository/archive integrity
  prune             Remove old archives per retention policy
  compact           Reclaim repository space
  info              Display repository statistics
  delete            Delete specific archive (requires --archive)
  extract           Restore files from archive (requires --archive --path)
  break-lock        Remove stale repository lock (for troubleshooting)

OPTIONS:
  -c, --config FILE/DIR    Config file or directory (default: ~/.config/tngbackup.conf)
  -r, --repo URI           Repository URI (overrides config)
  -p, --passphrase PASS    Repository passphrase (overrides config)
  --archive NAME           Archive name
  --path PATH              Restore path (for extract)
  --mountpoint PATH        Mount directory (default: /mnt/borg)
  -l, --log FILE           Log file path
  -V, --version            Show version and check for updates on GitHub
  -h, --help               Show this help

CONFIGURATION PATHS:
  Default:        ~/.config/tngbackup.conf
  System batch:   /etc/tngbackup/ (processes all *.conf files)
  Custom:         Use -c/--config to specify path or directory

EXAMPLES:
  tngbackup                                           # Interactive menu
  tngbackup -V                                        # Show version and check updates
  tngbackup backup --config ~/.config/tngbackup.conf  # Single backup
  tngbackup backup --config /etc/tngbackup/           # Batch mode (all *.conf files)
  tngbackup list --archive backup-20250904            # List archive contents
  tngbackup extract --archive backup-20250904 --path /home/user  # Restore

DOCUMENTATION:
  Full guide:    https://github.com/RedFoxy/TNGBackup
  Local docs:    README.md, docs/USAGE.md
  Migration:     docs/MIGRATION_it.md (Italian), docs/MIGRATION_en.md (English)

Author: Massimo "RedFoxy Darrest" Cicciò
License: CC BY-NC 4.0 (Non-Commercial) + Commercial License
HELPTEXT
}

load_config() {
    local config_file="$1"

    # Determine config path
    if [ -z "$config_file" ]; then
        config_file="$TNGB_CONFIG"
    fi

    # If config is a directory, process batch mode
    if [ -d "$config_file" ]; then
        load_config_batch "$config_file"
        return $?
    fi

    # Load single config file
    if [ -f "$config_file" ]; then
        debug "Loading config from: $config_file"
        # Source in current shell (not subshell) to keep variables
        source "$config_file" || {
            error "Failed to load config: $config_file"
            return 1
        }
    elif [ "$config_file" != "$TNGB_CONFIG" ]; then
        # User specified a config file that doesn't exist
        error "Config file not found: $config_file"
        return 1
    fi
    # If default config doesn't exist, just skip (use env/args)

    debug "Config loaded successfully"
    return 0
}

load_config_batch() {
    local config_dir="$1"
    local count=0
    local failed=0

    debug "Processing batch directory: $config_dir"

    # Process each .conf file in directory
    for config_file in "$config_dir"/*.conf; do
        [ -f "$config_file" ] || continue

        log "INFO" "Processing: $config_file"

        # Reset per-repository variables so settings never leak between configs
        REPO_URI=""
        REPO_PASSPHRASE=""
        BACKUP_PATH=""
        BACKUP_EXCLUDE=""
        ARCHIVE_NAME=""

        # Load this config
        source "$config_file" || {
            log "WARN" "Failed to load: $config_file, skipping"
            continue
        }

        # Validate and execute operation. A failure on one config must not
        # abort the whole batch.
        if validate_config; then
            dispatch_operation || {
                failed=$((failed + 1))
                log "WARN" "Operation '$OPERATION' failed for: $config_file"
            }
        else
            failed=$((failed + 1))
            log "WARN" "Config validation failed for: $config_file"
        fi

        count=$((count + 1))
    done

    log "INFO" "Batch processing complete: $count config(s) processed, $failed failed"

    if [ "$failed" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Dispatch OPERATION to the matching handler. Shared by single and batch mode.
dispatch_operation() {
    case "$OPERATION" in
        init)        borg_init ;;
        backup)      borg_backup ;;
        list)        borg_list ;;
        mount)       borg_mount ;;
        check)       borg_check ;;
        compact)     borg_compact ;;
        prune)       borg_prune ;;
        info)        borg_info ;;
        delete)      borg_delete ;;
        extract)     borg_extract ;;
        break-lock)  borg_break_lock ;;
        *)           error "Unknown operation: $OPERATION"; return 1 ;;
    esac
}

check_version() {
    echo "=================================="
    echo "TNGBackup v$SCRIPT_VERSION"
    echo "=================================="
    echo "$SCRIPT_DESC"
    echo ""
    echo "Author:   $SCRIPT_AUTHOR"
    echo "License:  $SCRIPT_LICENSE"
    echo "GitHub:   https://github.com/RedFoxy/TNGBackup"
    echo ""
    echo "Checking for updates on GitHub..."

    # Try to fetch the latest version from GitHub API
    if ! command -v curl &> /dev/null; then
        echo "curl not found - cannot check for updates"
        echo "Manual check: https://github.com/RedFoxy/TNGBackup/releases"
        return 0
    fi

    # Fetch GitHub API response with timeout
    local response=$(curl -s --max-time 5 "https://api.github.com/repos/RedFoxy/TNGBackup/releases/latest" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "Could not reach GitHub (check your internet connection)"
        echo "Manual check: https://github.com/RedFoxy/TNGBackup/releases"
        return 0
    fi

    # Try to parse with jq if available (more robust)
    local latest=""
    if command -v jq &> /dev/null; then
        latest=$(echo "$response" | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    else
        # Fallback to grep parsing with multiple patterns
        latest=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*' | head -1 | sed 's/.*"\([^"]*\)".*/\1/' | sed 's/^v//')
    fi

    if [ -z "$latest" ] || [ "$latest" = "null" ]; then
        echo "Could not parse GitHub response (API may be rate-limited)"
        echo "Manual check: https://github.com/RedFoxy/TNGBackup/releases"
        return 0
    fi

    # Compare versions
    if [ "$latest" != "$SCRIPT_VERSION" ]; then
        echo "New version available: v$latest"
        echo "Download: https://github.com/RedFoxy/TNGBackup/releases/latest"
    else
        echo "✓ You are running the latest version!"
    fi
}

parse_cli_args() {
    # Pre-process arguments to handle -p without value (interactive passphrase)
    local new_args=()
    local i=1
    local skip_next=0

    for arg in "$@"; do
        if [ "$skip_next" -eq 1 ]; then
            skip_next=0
            new_args+=("$arg")
            ((i++))
            continue
        fi

        if [ "$arg" = "-p" ] || [ "$arg" = "--passphrase" ]; then
            # Check if next argument exists and is not an option
            if [ $((i + 1)) -le $# ]; then
                eval "next_arg=\${$((i + 1))}"
                if [[ "$next_arg" == -* ]]; then
                    # Next is an option, so -p has no value: use placeholder
                    new_args+=("$arg" "__INTERACTIVE_PASSPHRASE__")
                else
                    # Next is a value: let getopt handle it normally
                    new_args+=("$arg")
                    skip_next=1
                fi
            else
                # Last argument: -p has no value: use placeholder
                new_args+=("$arg" "__INTERACTIVE_PASSPHRASE__")
            fi
        else
            new_args+=("$arg")
        fi
        ((i++))
    done

    # Parse arguments with getopt
    local opts
    opts=$(getopt -o c:r:p:l:hV \
        --long config:,repo:,passphrase:,archive:,path:,mountpoint:,log:,audit-log:,help,version \
        -n "tngbackup" -- "${new_args[@]}") || {
        show_help
        exit 1
    }

    eval set -- "$opts"

    local path_arg=""

    while true; do
        case "$1" in
            -c|--config)
                TNGB_CONFIG="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_URI="$2"
                shift 2
                ;;
            -p|--passphrase)
                if [ "$2" = "__INTERACTIVE_PASSPHRASE__" ]; then
                    # Interactive passphrase input (hidden)
                    read -s -p "Repository passphrase: " REPO_PASSPHRASE
                    echo ""  # New line after silent input
                else
                    REPO_PASSPHRASE="$2"
                fi
                shift 2
                ;;
            --archive)
                ARCHIVE_NAME="$2"
                shift 2
                ;;
            --path)
                path_arg="$2"
                shift 2
                ;;
            --mountpoint)
                MOUNT_PATH="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                # Create log file with restricted permissions
                touch "$LOG_FILE"
                chmod 600 "$LOG_FILE"
                shift 2
                ;;
            --audit-log)
                AUDIT_LOG_FILE="$2"
                touch "$AUDIT_LOG_FILE"
                chmod 600 "$AUDIT_LOG_FILE"
                shift 2
                ;;
            -V|--version)
                check_version
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                error "Invalid option: $1"
                exit 1
                ;;
        esac
    done

    # First positional argument is operation (if provided)
    if [ $# -gt 0 ]; then
        OPERATION="$1"
    fi

    # Map --path argument to appropriate variable based on operation
    if [ -n "$path_arg" ]; then
        case "$OPERATION" in
            backup) BACKUP_PATH="$path_arg" ;;
            extract) RESTORE_PATH="$path_arg" ;;
            *) RESTORE_PATH="$path_arg" ;;
        esac
    fi

    debug "CLI parsing complete: OPERATION=$OPERATION"
}

validate_config() {
    local required_vars=("REPO_URI" "REPO_PASSPHRASE")

    # Check required variables
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Missing required configuration: $var"
            return 1
        fi
    done

    # Check borg binary
    if ! command -v borg &>/dev/null; then
        error "borg binary not found in PATH"
        return 1
    fi

    # For backup operation, check BACKUP_PATH
    if [ "$OPERATION" = "backup" ] && [ -z "$BACKUP_PATH" ]; then
        error "BACKUP_PATH not set; no files to backup"
        return 1
    fi

    debug "Configuration validated successfully"
    return 0
}

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

show_menu() {
    echo ""
    echo "╔═══════════════════════════════════╗"
    echo "║      TNGBackup v2.0.0             ║"
    echo "╚═══════════════════════════════════╝"
    echo ""
    echo "  1) Initialize repository"
    echo "  2) Backup"
    echo "  3) List archives"
    echo "  4) Mount archive"
    echo "  5) Check repository"
    echo "  6) Prune old archives"
    echo "  7) Compact repository"
    echo "  8) Repository info"
    echo "  9) Extract files"
    echo " 10) Delete archive"
    echo ""
    echo "  0) Exit (default)"
    echo ""
    read -p "Select [0-10]: " choice
    choice="${choice:-0}"

    case "$choice" in
        0)  echo "Exiting..."; exit 0 ;;
        1)  OPERATION="init" ;;
        2)  OPERATION="backup" ;;
        3)  OPERATION="list" ;;
        4)  OPERATION="mount" ;;
        5)  OPERATION="check" ;;
        6)  OPERATION="prune" ;;
        7)  OPERATION="compact" ;;
        8)  OPERATION="info" ;;
        9)  OPERATION="extract" ;;
        10) OPERATION="delete" ;;
        *)  error "Invalid selection"; show_menu ;;
    esac

    debug "Menu selection: $choice -> $OPERATION"
}

# ============================================================================
# BORG OPERATIONS
# ============================================================================

calculate_duration() {
    local end_time=$(date +%s)
    echo $((end_time - START_TIME))
}

audit_log() {
    local operation="$1"
    local status="$2"
    local details="$3"
    local duration="$4"

    # Return silently if audit log not configured
    if [ -z "$AUDIT_LOG_FILE" ]; then
        return 0
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$timestamp | $operation | $status | $details | $duration" >> "$AUDIT_LOG_FILE"
}

borg_break_lock() {
    log "INFO" "Breaking stale repository lock: $REPO_URI"

    if [ -z "$REPO_URI" ] || [ -z "$REPO_PASSPHRASE" ]; then
        error "Missing REPO_URI or REPO_PASSPHRASE"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    setup_borg_env
    run_borg break-lock "$REPO_URI" 2>&1 | tee_log
    local rc=$?

    finish_operation "break-lock" "$rc" "$REPO_URI"
    return $?
}

borg_init() {
    log "INFO" "Initializing repository: $REPO_URI"

    if [ -z "$REPO_URI" ] || [ -z "$REPO_PASSPHRASE" ]; then
        error "Missing REPO_URI or REPO_PASSPHRASE"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    setup_borg_env

    local rc=0
    run_borg init --encryption="$BORG_ENCRYPTION" "$REPO_URI" || rc=$?

    finish_operation "init" "$rc" "$REPO_URI"
}

borg_backup() {
    log "INFO" "Starting backup from: $BACKUP_PATH"

    if [ -z "$BACKUP_PATH" ]; then
        error "BACKUP_PATH not set"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    # Generate archive name if not provided
    if [ -z "$ARCHIVE_NAME" ]; then
        ARCHIVE_NAME="archive-$(date +%Y%m%d-%H%M%S)"
    fi

    setup_borg_env

    # Build the argument list as an array: no eval, no quoting surprises,
    # and paths containing spaces are handled correctly.
    local args=()

    # BORG_OPT is intentionally word-split: it holds user supplied flags.
    if [ -n "$BORG_OPT" ]; then
        # shellcheck disable=SC2206
        args+=($BORG_OPT)
    fi

    # BACKUP_EXCLUDE is a semicolon separated list of patterns
    if [ -n "$BACKUP_EXCLUDE" ]; then
        local exclude_list=()
        IFS=';' read -ra exclude_list <<< "$BACKUP_EXCLUDE"
        local exclude_item
        for exclude_item in "${exclude_list[@]}"; do
            if [ -n "$exclude_item" ]; then
                args+=(--exclude "$exclude_item")
            fi
        done
    fi

    args+=("::$ARCHIVE_NAME")

    # BACKUP_PATH may list several space separated paths
    # shellcheck disable=SC2206
    local backup_targets=($BACKUP_PATH)
    args+=("${backup_targets[@]}")

    local rc=0
    run_borg create "${args[@]}" || rc=$?

    finish_operation "backup" "$rc" "$ARCHIVE_NAME"
}

borg_list() {
    setup_borg_env

    local rc=0
    local details="all-archives"

    if [ -n "$ARCHIVE_NAME" ]; then
        log "INFO" "Listing contents of archive: $ARCHIVE_NAME"
        details="$ARCHIVE_NAME"
        run_borg list "::$ARCHIVE_NAME" || rc=$?
    else
        log "INFO" "Listing all archives in repository"
        run_borg list || rc=$?
    fi

    finish_operation "list" "$rc" "$details"
}

borg_check() {
    log "INFO" "Checking repository: $REPO_URI"

    setup_borg_env

    local rc=0
    local details="repository"

    if [ -n "$ARCHIVE_NAME" ]; then
        details="$ARCHIVE_NAME"
        run_borg check "::$ARCHIVE_NAME" || rc=$?
    else
        run_borg check --repository-only || rc=$?
    fi

    finish_operation "check" "$rc" "$details"
}

borg_prune() {
    log "INFO" "Pruning repository: $REPO_URI"

    setup_borg_env

    local retention=()
    mapfile -t retention < <(build_retention_opts || true)

    if [ "${#retention[@]}" -eq 0 ]; then
        error "No retention policy configured (set at least one of KEEP_LAST, KEEP_HOURLY, KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY, KEEP_YEARLY)"
        OPERATION_STATUS="FAILED"
        audit_log "prune" "FAILED" "no retention policy" "$(calculate_duration)"
        return 1
    fi

    debug "Retention policy: ${retention[*]}"

    local rc=0
    run_borg prune --list "${retention[@]}" || rc=$?

    finish_operation "prune" "$rc" "${retention[*]}"
}

borg_compact() {
    log "INFO" "Compacting repository: $REPO_URI"

    setup_borg_env

    local rc=0
    run_borg compact || rc=$?

    finish_operation "compact" "$rc" "$REPO_URI"
}

borg_info() {
    setup_borg_env

    local rc=0
    local details="repository"

    if [ -n "$ARCHIVE_NAME" ]; then
        log "INFO" "Retrieving info for archive: $ARCHIVE_NAME"
        details="$ARCHIVE_NAME"
        run_borg info "::$ARCHIVE_NAME" || rc=$?
    else
        log "INFO" "Retrieving repository info: $REPO_URI"
        run_borg info || rc=$?
    fi

    finish_operation "info" "$rc" "$details"
}

borg_mount() {
    if [ -z "$MOUNT_PATH" ]; then
        error "MOUNT_PATH not set (use --mountpoint)"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    setup_borg_env

    # Create the mountpoint if it does not exist yet
    if [ ! -d "$MOUNT_PATH" ]; then
        debug "Creating mountpoint: $MOUNT_PATH"
        if [ "$DRYRUN" != "y" ]; then
            mkdir -p "$MOUNT_PATH" || {
                error "Cannot create mountpoint: $MOUNT_PATH"
                OPERATION_STATUS="FAILED"
                return 1
            }
        fi
    fi

    local rc=0
    local details="$MOUNT_PATH"

    if [ -n "$ARCHIVE_NAME" ]; then
        log "INFO" "Mounting archive $ARCHIVE_NAME on $MOUNT_PATH"
        details="$ARCHIVE_NAME -> $MOUNT_PATH"
        run_borg mount "::$ARCHIVE_NAME" "$MOUNT_PATH" || rc=$?
    else
        log "INFO" "Mounting repository on $MOUNT_PATH"
        run_borg mount "$REPO_URI" "$MOUNT_PATH" || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        log "INFO" "Unmount with: borg umount $MOUNT_PATH"
        # The cleanup trap must not unmount what the user just asked for.
        MOUNT_PATH=""
    fi

    finish_operation "mount" "$rc" "$details"
}

borg_delete() {
    if [ -z "$ARCHIVE_NAME" ]; then
        error "delete requires --archive NAME"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    log "INFO" "Deleting archive: $ARCHIVE_NAME"

    setup_borg_env

    local rc=0
    run_borg delete "::$ARCHIVE_NAME" || rc=$?

    finish_operation "delete" "$rc" "$ARCHIVE_NAME"
}

borg_extract() {
    if [ -z "$ARCHIVE_NAME" ]; then
        error "extract requires --archive NAME"
        OPERATION_STATUS="FAILED"
        return 1
    fi

    setup_borg_env

    # borg extract always restores relative to the current directory
    local target="${RESTORE_PATH:-$PWD}"

    if [ ! -d "$target" ]; then
        debug "Creating restore directory: $target"
        if [ "$DRYRUN" != "y" ]; then
            mkdir -p "$target" || {
                error "Cannot create restore path: $target"
                OPERATION_STATUS="FAILED"
                return 1
            }
        fi
    fi

    log "INFO" "Extracting archive $ARCHIVE_NAME into $target"

    local rc=0
    if [ "$DRYRUN" = "y" ]; then
        log "INFO" "[DRY-RUN] (cd $target && borg extract ::$ARCHIVE_NAME)"
    else
        (
            cd "$target" || exit 1
            borg extract "::$ARCHIVE_NAME" < /dev/null 2>&1
        ) | tee_log || rc=$?
    fi

    finish_operation "extract" "$rc" "$ARCHIVE_NAME -> $target"
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

cleanup() {
    debug "Executing cleanup..."

    # Unset all credential variables
    unset REPO_URI REPO_PASSPHRASE BACKUP_PATH
    unset TNGB_REPO_URI TNGB_PASSPHRASE TNGB_BACKUP_PATH
    unset BORG_PASSPHRASE BORG_RSH

    # Destroy temp config (if created)
    if [ -n "$TEMP_CONFIG" ] && [ -f "$TEMP_CONFIG" ]; then
        shred -vfz -n 3 "$TEMP_CONFIG" 2>/dev/null || rm -f "$TEMP_CONFIG"
        debug "Temp config destroyed"
    fi

    # Umount any Borg mounts (graceful)
    if [ -n "$MOUNT_PATH" ] && mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        debug "Unmounting: $MOUNT_PATH"
        borg umount "$MOUNT_PATH" 2>/dev/null || true
    fi

    debug "Cleanup complete"
}

# Install trap handlers
trap cleanup EXIT
trap cleanup INT
trap cleanup TERM

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    START_TIME=$(date +%s)

    # Parse CLI arguments
    parse_cli_args "$@"

    # If no operation was given, check if config exists:
    # - If config doesn't exist: show help (guidance for new users)
    # - If config exists: show interactive menu
    if [ -z "$OPERATION" ]; then
        if [ ! -e "$TNGB_CONFIG" ] && [ ! -d "$TNGB_CONFIG" ]; then
            # No config file/directory found and no operation specified: show help
            show_help
            exit 0
        fi
        # Config exists: show interactive menu
        show_menu
    fi

    # CLI overrides must survive the config file, which is sourced afterwards.
    local cli_repo="$REPO_URI"
    local cli_passphrase="$REPO_PASSPHRASE"

    # Load configuration (file/directory). A directory triggers batch mode and
    # runs the operation for every config it contains.
    local rc=0
    if [ -d "$TNGB_CONFIG" ]; then
        load_config "$TNGB_CONFIG" || rc=$?
        local end_time=$(date +%s)
        log "INFO" "Batch run completed in $((end_time - START_TIME))s"
        exit "$rc"
    fi

    if ! load_config "$TNGB_CONFIG"; then
        error "Failed to load configuration"
        exit 1
    fi

    # Re-apply the CLI overrides on top of the config file values
    if [ -n "$cli_repo" ]; then
        REPO_URI="$cli_repo"
    fi
    if [ -n "$cli_passphrase" ]; then
        REPO_PASSPHRASE="$cli_passphrase"
    fi

    # Validate configuration
    if ! validate_config; then
        error "Configuration validation failed"
        exit 1
    fi

    # Execute operation
    dispatch_operation || rc=$?

    # Record operation status
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    log "INFO" "Operation '$OPERATION' finished with status ${OPERATION_STATUS:-UNKNOWN} in ${duration}s"

    exit "$rc"
}

main "$@"
