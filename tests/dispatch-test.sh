#!/bin/bash
#
# TNGBackup dispatch test
#
# Verifies argument handling, operation dispatch, config loading, batch mode and
# audit logging WITHOUT a real Borg installation: a stub `borg` is put first on
# PATH and records the command line it was invoked with.
#
# This complements tests/integration-test.sh, which needs a real Borg and
# exercises actual repositories.
#
# Usage: ./tests/dispatch-test.sh
# Exit codes: 0 all passed, 1 failures
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TNGBACKUP="${TNGBACKUP:-$REPO_ROOT/tngbackup}"

PASSED=0
FAILED=0
FAILED_NAMES=()

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/tngbackup-dtest.XXXXXX")"

cleanup() { [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

pass() { PASSED=$((PASSED + 1)); echo "  [PASS] $1"; }
failed() {
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$1")
    echo "  [FAIL] $1"
    [ -n "${2:-}" ] && echo "         ${2//$'\n'/$'\n'         }"
}

# --- stub borg -------------------------------------------------------------

BIN="$WORKDIR/bin"
mkdir -p "$BIN"
CALLS="$WORKDIR/borg-calls.log"

cat > "$BIN/borg" <<'STUB'
#!/bin/bash
echo "borg $*" >> "$BORG_CALLS"
case "$1" in
    --version) echo "borg 1.2.8" ;;
    info)      echo "Repository ID: stub" ;;
    list)      echo "stub-archive  Thu, 2026-01-01 00:00:00" ;;
    fail-me)   exit 2 ;;
esac
exit "${BORG_STUB_EXIT:-0}"
STUB
chmod +x "$BIN/borg"

export BORG_CALLS="$CALLS"
export PATH="$BIN:$PATH"

CONFIG="$WORKDIR/test.conf"
LOG="$WORKDIR/run.log"
AUDIT="$WORKDIR/audit.log"

cat > "$CONFIG" <<EOF
REPO_URI="$WORKDIR/repo"
REPO_PASSPHRASE="secret-passphrase"
BACKUP_PATH="$WORKDIR/data"
BACKUP_EXCLUDE="*/cache/*;*.tmp"
KEEP_LAST="5"
KEEP_DAILY="7"
SHOWTEXT="n"
EOF
mkdir -p "$WORKDIR/data"

run_tngb() {
    : > "$CALLS"
    OUT="$("$TNGBACKUP" "$@" --config "$CONFIG" --log "$LOG" --audit-log "$AUDIT" 2>&1)"
    RC=$?
    CALLED="$(cat "$CALLS" 2>/dev/null)"
    return $RC
}

echo ""
echo "=== Dispatch test (stub borg) ==="
echo "tngbackup: $TNGBACKUP"

# --- each operation reaches the right borg subcommand ----------------------

check_op() {
    local op="$1" expect="$2"; shift 2
    if run_tngb "$op" "$@"; then
        if printf '%s' "$CALLED" | grep -q -- "$expect"; then
            pass "$op -> $expect"
        else
            failed "$op" "expected '$expect', borg was called with: ${CALLED:-<nothing>}"
        fi
    else
        failed "$op" "exit $RC: $OUT"
    fi
}

check_op init    "borg init --encryption=repokey-blake2"
check_op backup  "borg create"
check_op list    "borg list"
check_op info    "borg info"
check_op check   "borg check --repository-only"
check_op prune   "borg prune"
check_op compact "borg compact"
check_op delete  "borg delete ::a1"   --archive a1
check_op extract "borg extract ::a1"  --archive a1 --path "$WORKDIR/restore"
check_op mount   "borg mount"         --archive a1 --mountpoint "$WORKDIR/mnt"

# --- argument construction -------------------------------------------------

echo ""
echo "=== Argument handling ==="

if run_tngb backup --archive myarch; then
    if printf '%s' "$CALLED" | grep -q -- "--exclude \*/cache/\* --exclude \*.tmp"; then
        pass "BACKUP_EXCLUDE expands to one --exclude per pattern"
    else
        failed "BACKUP_EXCLUDE" "borg was called with: $CALLED"
    fi
    if printf '%s' "$CALLED" | grep -q -- "::myarch"; then
        pass "--archive overrides the generated archive name"
    else
        failed "--archive" "borg was called with: $CALLED"
    fi
else
    failed "backup argument handling" "exit $RC: $OUT"
fi

if run_tngb prune; then
    if printf '%s' "$CALLED" | grep -q -- "--keep-last=5" &&
       printf '%s' "$CALLED" | grep -q -- "--keep-daily=7"; then
        pass "prune builds the retention options from KEEP_*"
    else
        failed "prune retention" "borg was called with: $CALLED"
    fi
else
    failed "prune retention" "exit $RC: $OUT"
fi

# Every retention rule disabled -> prune must refuse instead of deleting everything
NORET="$WORKDIR/noretention.conf"
{
    grep -v '^KEEP_' "$CONFIG"
    echo 'KEEP_LAST="0"'
    echo 'KEEP_HOURLY="0"'
    echo 'KEEP_DAILY="0"'
    echo 'KEEP_WEEKLY="0"'
    echo 'KEEP_MONTHLY="0"'
    echo 'KEEP_YEARLY="0"'
} > "$NORET"
if "$TNGBACKUP" prune --config "$NORET" --audit-log "$AUDIT" >/dev/null 2>&1; then
    failed "prune without retention" "should have failed but exited 0"
else
    pass "prune refuses to run with no retention policy"
fi

# delete without --archive must fail
if "$TNGBACKUP" delete --config "$CONFIG" >/dev/null 2>&1; then
    failed "delete without --archive" "should have failed but exited 0"
else
    pass "delete without --archive is rejected"
fi

# --- dry run ---------------------------------------------------------------

echo ""
echo "=== Dry run ==="
: > "$CALLS"
if DRYRUN=y "$TNGBACKUP" backup --config "$CONFIG" >/dev/null 2>&1; then
    if [ ! -s "$CALLS" ]; then
        pass "DRYRUN=y executes no borg command"
    else
        failed "DRYRUN" "borg was still invoked: $(cat "$CALLS")"
    fi
else
    failed "DRYRUN" "backup exited non-zero in dry-run mode"
fi

# --- failure propagation ---------------------------------------------------

echo ""
echo "=== Failure handling ==="
if BORG_STUB_EXIT=2 "$TNGBACKUP" backup --config "$CONFIG" --audit-log "$AUDIT" >/dev/null 2>&1; then
    failed "borg failure propagation" "tngbackup returned 0 while borg failed"
else
    pass "a failing borg command makes tngbackup exit non-zero"
fi

if grep -q "| backup | FAILED |" "$AUDIT" 2>/dev/null; then
    pass "failures are recorded in the audit log"
else
    failed "audit FAILED record" "no FAILED backup record in $AUDIT"
fi

# Borg exit 1 means "completed with warnings": the archive exists, so the run
# must not be reported as a failure.
if BORG_STUB_EXIT=1 "$TNGBACKUP" backup --config "$CONFIG" --audit-log "$AUDIT" >/dev/null 2>&1; then
    pass "borg exit 1 (warnings) is not treated as a failure"
else
    failed "warning handling" "tngbackup exited non-zero on borg exit code 1"
fi

if grep -q "| backup | WARNING |" "$AUDIT" 2>/dev/null; then
    pass "warnings are recorded in the audit log"
else
    failed "audit WARNING record" "no WARNING backup record in $AUDIT"
fi

# --- audit log -------------------------------------------------------------

echo ""
echo "=== Audit log ==="
if [ -f "$AUDIT" ]; then
    pass "audit log created"
    if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \| [a-z]+ \| (SUCCESS|WARNING|FAILED) \|' "$AUDIT"; then
        pass "audit records match the documented format"
    else
        failed "audit format" "$(head -3 "$AUDIT")"
    fi
else
    failed "audit log" "not created"
fi

if grep -q "secret-passphrase" "$LOG" "$AUDIT" 2>/dev/null; then
    failed "credential leak" "the passphrase appears in a log file"
else
    pass "no passphrase leaked into the logs"
fi

# --- batch mode ------------------------------------------------------------

echo ""
echo "=== Batch mode ==="
BATCH="$WORKDIR/batch"
mkdir -p "$BATCH"
for name in one two three; do
    cat > "$BATCH/$name.conf" <<EOF
REPO_URI="$WORKDIR/repo-$name"
REPO_PASSPHRASE="secret-passphrase"
BACKUP_PATH="$WORKDIR/data"
SHOWTEXT="n"
EOF
done

: > "$CALLS"
if "$TNGBACKUP" backup --config "$BATCH" >/dev/null 2>&1; then
    created="$(grep -c "borg create" "$CALLS" 2>/dev/null || echo 0)"
    if [ "$created" -eq 3 ]; then
        pass "batch mode processed all 3 config files"
    else
        failed "batch mode" "expected 3 borg create calls, got $created"
    fi
else
    failed "batch mode" "batch run exited non-zero"
fi

# --- help ------------------------------------------------------------------

echo ""
echo "=== Help ==="
if "$TNGBACKUP" --help 2>&1 | grep -q "USAGE: tngbackup"; then
    pass "--help prints usage"
else
    failed "--help" "usage banner not found"
fi

if "$TNGBACKUP" bogus-op --config "$CONFIG" >/dev/null 2>&1; then
    failed "unknown operation" "should have failed but exited 0"
else
    pass "unknown operation is rejected"
fi

# --- report ----------------------------------------------------------------

echo ""
echo "=== Result ==="
TOTAL=$((PASSED + FAILED))
echo "Passed: $PASSED/$TOTAL"

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: all dispatch checks passed"
    exit 0
fi

echo "Failed: $FAILED"
for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
echo "FAIL"
exit 1
