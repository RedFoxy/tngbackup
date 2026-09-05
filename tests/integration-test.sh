#!/bin/bash
#
# TNGBackup end-to-end integration test
#
# Creates a throwaway Borg repository in a temporary directory, exercises every
# operation against it, verifies the audit log, then removes everything.
#
# Requirements: bash 4+, borg 1.2+
# Usage:
#   ./tests/integration-test.sh
#   TNGB_TEST_MOUNT=y ./tests/integration-test.sh   # also exercise mount (needs FUSE)
#
# Exit codes: 0 all tests passed, 1 one or more tests failed, 2 prerequisites missing
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TNGBACKUP="${TNGBACKUP:-$REPO_ROOT/tngbackup}"

TEST_MOUNT="${TNGB_TEST_MOUNT:-n}"

PASSED=0
FAILED=0
FAILED_NAMES=()

WORKDIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

say()  { echo "$*"; }
head1() { echo ""; echo "=== $* ==="; }

pass() {
    PASSED=$((PASSED + 1))
    echo "  [PASS] $1"
}

failed() {
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$1")
    echo "  [FAIL] $1"
    if [ -n "${2:-}" ]; then
        echo "         $2"
    fi
}

cleanup() {
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        # Make sure nothing is still mounted before deleting
        if [ -d "$WORKDIR/mnt" ] && mountpoint -q "$WORKDIR/mnt" 2>/dev/null; then
            borg umount "$WORKDIR/mnt" 2>/dev/null || true
        fi
        rm -rf "$WORKDIR"
        say "Removed temporary workdir: $WORKDIR"
    fi
}
trap cleanup EXIT INT TERM

# Run tngbackup with the test config; capture combined output in TEST_OUTPUT.
run_tngb() {
    TEST_OUTPUT="$("$TNGBACKUP" "$@" --config "$CONFIG" --log "$LOG" --audit-log "$AUDIT" 2>&1)"
    return $?
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

head1 "Prerequisites"

if [ ! -x "$TNGBACKUP" ]; then
    if [ -f "$TNGBACKUP" ]; then
        echo "[ERROR] $TNGBACKUP is not executable (run: chmod +x tngbackup)" >&2
    else
        echo "[ERROR] tngbackup not found at: $TNGBACKUP" >&2
    fi
    exit 2
fi
say "tngbackup: $TNGBACKUP"

if ! command -v borg >/dev/null 2>&1; then
    echo "[ERROR] borg not found in PATH - cannot run the integration test." >&2
    echo "        Install BorgBackup 1.2+ and re-run this script." >&2
    exit 2
fi
say "borg: $(borg --version 2>&1)"

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "[ERROR] Bash 4+ required (found $BASH_VERSION)" >&2
    exit 2
fi
say "bash: $BASH_VERSION"

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

head1 "Setup"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/tngbackup-itest.XXXXXX")"
REPO="$WORKDIR/repo"
DATA="$WORKDIR/data"
RESTORE="$WORKDIR/restore"
CONFIG="$WORKDIR/test.conf"
LOG="$WORKDIR/tngbackup.log"
AUDIT="$WORKDIR/audit.log"
ARCHIVE="itest-archive"
PASSPHRASE="integration-test-passphrase"

mkdir -p "$DATA/subdir" "$DATA/cache" "$RESTORE"
echo "hello tngbackup" > "$DATA/file1.txt"
echo "second file"     > "$DATA/subdir/file2.txt"
echo "should be excluded" > "$DATA/cache/junk.tmp"

cat > "$CONFIG" <<EOF
REPO_URI="$REPO"
REPO_PASSPHRASE="$PASSPHRASE"
BACKUP_PATH="$DATA"
BACKUP_EXCLUDE="*/cache/*"
BORG_ENCRYPTION="repokey-blake2"
KEEP_LAST="3"
KEEP_DAILY="7"
SHOWTEXT="y"
EOF
chmod 600 "$CONFIG"

say "Workdir: $WORKDIR"
say "Repo:    $REPO"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

head1 "Operations"

# 1. init
if run_tngb init && [ -f "$REPO/config" ]; then
    pass "init - repository created"
else
    failed "init" "$TEST_OUTPUT"
fi

# 2. backup
if run_tngb backup --archive "$ARCHIVE"; then
    pass "backup - archive created"
else
    failed "backup" "$TEST_OUTPUT"
fi

# 3. list (all archives)
if run_tngb list && printf '%s' "$TEST_OUTPUT" | grep -q "$ARCHIVE"; then
    pass "list - archive present in repository listing"
else
    failed "list" "$TEST_OUTPUT"
fi

# 4. list --archive (archive contents + exclude honoured)
if run_tngb list --archive "$ARCHIVE"; then
    if printf '%s' "$TEST_OUTPUT" | grep -q "file1.txt"; then
        if printf '%s' "$TEST_OUTPUT" | grep -q "junk.tmp"; then
            failed "list --archive" "BACKUP_EXCLUDE was not honoured: junk.tmp is in the archive"
        else
            pass "list --archive - contents listed, exclude honoured"
        fi
    else
        failed "list --archive" "file1.txt missing from the archive listing"
    fi
else
    failed "list --archive" "$TEST_OUTPUT"
fi

# 5. info
if run_tngb info && printf '%s' "$TEST_OUTPUT" | grep -qi "repository"; then
    pass "info - repository statistics returned"
else
    failed "info" "$TEST_OUTPUT"
fi

# 6. check
if run_tngb check; then
    pass "check - repository integrity verified"
else
    failed "check" "$TEST_OUTPUT"
fi

# 7. prune
if run_tngb prune; then
    pass "prune - retention policy applied"
else
    failed "prune" "$TEST_OUTPUT"
fi

# 8. compact
if run_tngb compact; then
    pass "compact - repository compacted"
else
    failed "compact" "$TEST_OUTPUT"
fi

# 9. extract
if run_tngb extract --archive "$ARCHIVE" --path "$RESTORE"; then
    if find "$RESTORE" -name file1.txt -print -quit | grep -q .; then
        pass "extract - files restored"
    else
        failed "extract" "file1.txt not found under $RESTORE"
    fi
else
    failed "extract" "$TEST_OUTPUT"
fi

# 10. mount (optional: requires FUSE and llfuse/pyfuse3)
if [ "$TEST_MOUNT" = "y" ]; then
    mkdir -p "$WORKDIR/mnt"
    if run_tngb mount --archive "$ARCHIVE" --mountpoint "$WORKDIR/mnt"; then
        if [ -n "$(ls -A "$WORKDIR/mnt" 2>/dev/null)" ]; then
            pass "mount - archive mounted"
        else
            failed "mount" "mountpoint is empty"
        fi
        borg umount "$WORKDIR/mnt" 2>/dev/null || true
    else
        failed "mount" "$TEST_OUTPUT"
    fi
else
    say "  [SKIP] mount - set TNGB_TEST_MOUNT=y to exercise it (requires FUSE)"
fi

# 11. delete
if run_tngb delete --archive "$ARCHIVE"; then
    if run_tngb list && ! printf '%s' "$TEST_OUTPUT" | grep -q "$ARCHIVE"; then
        pass "delete - archive removed"
    else
        failed "delete" "archive still listed after delete"
    fi
else
    failed "delete" "$TEST_OUTPUT"
fi

# ---------------------------------------------------------------------------
# Audit log verification
# ---------------------------------------------------------------------------

head1 "Audit log"

if [ -f "$AUDIT" ]; then
    pass "audit log created: $AUDIT"

    # Format: TIMESTAMP | operation | status | details | duration
    if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \| [a-z]+ \| (SUCCESS|WARNING|FAILED) \|' "$AUDIT"; then
        pass "audit log format is valid"
    else
        failed "audit log format" "no record matched the expected format"
    fi

    missing=()
    for op in init backup list info check prune compact extract delete; do
        if ! grep -q "| $op |" "$AUDIT"; then
            missing+=("$op")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        pass "audit log records every executed operation"
    else
        failed "audit log coverage" "missing records for: ${missing[*]}"
    fi
else
    failed "audit log" "file not created: $AUDIT"
fi

if [ -f "$LOG" ] && [ -s "$LOG" ]; then
    pass "run log written: $LOG"
else
    failed "run log" "log file missing or empty: $LOG"
fi

# Credentials must never be written to the logs
if grep -q "$PASSPHRASE" "$LOG" "$AUDIT" 2>/dev/null; then
    failed "credential leak" "the passphrase appears in a log file"
else
    pass "no passphrase leaked into the logs"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

head1 "Result"

TOTAL=$((PASSED + FAILED))
say "Passed: $PASSED/$TOTAL"

if [ "$FAILED" -eq 0 ]; then
    say "PASS: All operations tested successfully"
    exit 0
fi

say "Failed: $FAILED"
for name in "${FAILED_NAMES[@]}"; do
    say "  - $name"
done
say "FAIL: $FAILED check(s) failed"
exit 1
