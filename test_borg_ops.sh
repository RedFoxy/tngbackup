#!/bin/bash

# Source the functions
source v2/classi/functions.sh
source v2/classi/borg_check.sh
source v2/classi/borg_compact.sh
source v2/classi/borg_mount.sh

# Setup test environment
export DEBUG="y"
export DRYRUN="y"
export REPO_PASSPHRASE="test_passphrase"
export LOCAL_REPO="/tmp/test-repo"
export MOUNT_PATH="/tmp/test-mount"
export AUDIT_LOG_FILE="/tmp/audit_test.log"
export Local_SKIP=0
export Remote_SKIP=0

# Clear test audit log
rm -f /tmp/audit_test.log

echo "=== Testing borg_check return code ==="
borg_check local
echo "Return code: $?"
echo ""

echo "=== Testing borg_compact return code ==="
borg_compact local
echo "Return code: $?"
echo ""

echo "=== Testing borg_mount return code ==="
borg_mount local
echo "Return code: $?"
echo ""

echo "=== Audit Log Entries ==="
if [ -f "/tmp/audit_test.log" ]; then
  grep -E "check|compact|mount" /tmp/audit_test.log
fi
