#!/bin/bash
#
# TNGBackup installer
#
# Installs the tngbackup utility to a system location, prepares the log files
# and (optionally) installs the man page and the systemd unit templates.
#
# Usage:
#   sudo ./install.sh                 # install to /usr/local/bin
#   PREFIX=$HOME/.local ./install.sh  # install to a custom prefix
#   ./install.sh --uninstall          # remove the installed files
#

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
MAN_DIR="${MAN_DIR:-$PREFIX/share/man/man1}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
CONFIG_FILE="${CONFIG_FILE:-/etc/tngbackup.conf}"
LOG_FILE="${LOG_FILE:-/var/log/tngbackup.log}"
AUDIT_LOG_FILE="${AUDIT_LOG_FILE:-/var/log/tngbackup-audit.log}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/tngbackup"

MIN_BASH_MAJOR=4
MIN_BORG_MAJOR=1
MIN_BORG_MINOR=2

info()  { echo "[INFO] $*"; }
warn()  { echo "[WARN] $*" >&2; }
fail()  { echo "[ERROR] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Requirement checks
# ---------------------------------------------------------------------------

check_bash() {
    local major="${BASH_VERSINFO[0]}"
    if [ "$major" -lt "$MIN_BASH_MAJOR" ]; then
        fail "Bash ${MIN_BASH_MAJOR}.0 or newer is required (found ${BASH_VERSION})"
    fi
    info "Bash ${BASH_VERSION} - OK"
}

check_borg() {
    if ! command -v borg >/dev/null 2>&1; then
        fail "borg not found in PATH. Install BorgBackup ${MIN_BORG_MAJOR}.${MIN_BORG_MINOR}+ first."
    fi

    local version_line version major minor
    version_line="$(borg --version 2>/dev/null || true)"
    # "borg 1.2.8" -> "1.2.8"
    version="$(printf '%s\n' "$version_line" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"

    if [ -z "$version" ]; then
        warn "Could not determine the Borg version from: $version_line"
        return 0
    fi

    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"

    if [ "$major" -lt "$MIN_BORG_MAJOR" ] ||
       { [ "$major" -eq "$MIN_BORG_MAJOR" ] && [ "$minor" -lt "$MIN_BORG_MINOR" ]; }; then
        fail "Borg ${MIN_BORG_MAJOR}.${MIN_BORG_MINOR} or newer is required (found ${version})"
    fi

    info "Borg ${version} - OK"
}

check_optional_tools() {
    local tool
    for tool in getopt ssh; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            warn "'$tool' not found: some features will not work"
        fi
    done
}

# ---------------------------------------------------------------------------
# Install / uninstall
# ---------------------------------------------------------------------------

install_binary() {
    [ -f "$SOURCE_SCRIPT" ] || fail "Source script not found: $SOURCE_SCRIPT"

    install -d "$BIN_DIR" || fail "Cannot create $BIN_DIR (try running with sudo)"
    install -m 0755 "$SOURCE_SCRIPT" "$BIN_DIR/tngbackup" ||
        fail "Cannot install to $BIN_DIR (try running with sudo)"

    info "Installed $BIN_DIR/tngbackup"
}

install_logs() {
    local f
    for f in "$LOG_FILE" "$AUDIT_LOG_FILE"; do
        local dir
        dir="$(dirname "$f")"
        if ! install -d "$dir" 2>/dev/null; then
            warn "Cannot create log directory: $dir"
            continue
        fi
        if [ ! -e "$f" ]; then
            if : > "$f" 2>/dev/null; then
                chmod 600 "$f"
                info "Created log file $f (mode 600)"
            else
                warn "Cannot create log file: $f"
            fi
        else
            chmod 600 "$f" 2>/dev/null || true
            info "Log file already present: $f"
        fi
    done
}

install_manpage() {
    local man_src="$SCRIPT_DIR/docs/tngbackup.1"
    if [ ! -f "$man_src" ]; then
        return 0
    fi
    if install -d "$MAN_DIR" 2>/dev/null && install -m 0644 "$man_src" "$MAN_DIR/tngbackup.1" 2>/dev/null; then
        info "Installed man page to $MAN_DIR/tngbackup.1"
    else
        warn "Could not install the man page to $MAN_DIR"
    fi
}

install_config_template() {
    local template="$SCRIPT_DIR/docs/examples/local-backup.conf"
    [ -f "$template" ] || template="$SCRIPT_DIR/example.conf"
    [ -f "$template" ] || return 0

    if [ -e "$CONFIG_FILE" ]; then
        info "Config already present, left untouched: $CONFIG_FILE"
        return 0
    fi

    if install -m 0600 "$template" "$CONFIG_FILE" 2>/dev/null; then
        info "Installed config template to $CONFIG_FILE (mode 600) - edit it before use"
    else
        warn "Could not install the config template to $CONFIG_FILE"
    fi
}

install_systemd_units() {
    local unit
    for unit in tngbackup.service tngbackup.timer; do
        local src="$SCRIPT_DIR/docs/$unit"
        [ -f "$src" ] || continue
        if [ -d "$SYSTEMD_DIR" ] && install -m 0644 "$src" "$SYSTEMD_DIR/$unit" 2>/dev/null; then
            info "Installed systemd unit $SYSTEMD_DIR/$unit"
        else
            warn "Could not install $unit to $SYSTEMD_DIR (install it manually if needed)"
        fi
    done
}

uninstall() {
    local f
    for f in "$BIN_DIR/tngbackup" "$MAN_DIR/tngbackup.1" \
             "$SYSTEMD_DIR/tngbackup.service" "$SYSTEMD_DIR/tngbackup.timer"; do
        if [ -e "$f" ]; then
            rm -f "$f" && info "Removed $f"
        fi
    done
    info "Config and log files were left in place: $CONFIG_FILE, $LOG_FILE, $AUDIT_LOG_FILE"
    info "TNGBackup uninstalled"
}

main() {
    if [ "${1:-}" = "--uninstall" ]; then
        uninstall
        exit 0
    fi

    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
    fi

    info "Checking requirements..."
    check_bash
    check_borg
    check_optional_tools

    info "Installing..."
    install_binary
    install_logs
    install_manpage
    install_config_template
    install_systemd_units

    echo ""
    echo "TNGBackup installed to $BIN_DIR/tngbackup"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the configuration:  $CONFIG_FILE"
    echo "  2. Initialize a repository: tngbackup init"
    echo "  3. Run a backup:            tngbackup backup"
    echo "  4. Read the full guide:     docs/USAGE.md"
}

main "$@"
