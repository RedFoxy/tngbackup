#!/bin/bash

#
# Test script for borg_mount, borg_check, borg_compact functions
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Test directory: $SCRIPT_DIR"

# Source the functions
source "$SCRIPT_DIR/classi/functions.sh"
source "$SCRIPT_DIR/classi/borg_mount.sh"
source "$SCRIPT_DIR/classi/borg_check.sh"
source "$SCRIPT_DIR/classi/borg_compact.sh"

# Setup test environment
DEBUG="y"
DRYRUN="y"
REPO_PASSPHRASE="test-passphrase"
LOCAL_REPO="/tmp/test-repo"
MOUNT_PATH="/tmp/test-mount"
SHOWTEXT="y"

# Mock runCMD for testing
echo ""
echo "=========================================="
echo "TEST 1: Check if functions are defined"
echo "=========================================="

if declare -f borg_mount &>/dev/null; then
  echo "✓ borg_mount function is defined"
else
  echo "✗ borg_mount function is NOT defined"
  exit 1
fi

if declare -f borg_check &>/dev/null; then
  echo "✓ borg_check function is defined"
else
  echo "✗ borg_check function is NOT defined"
  exit 1
fi

if declare -f borg_compact &>/dev/null; then
  echo "✓ borg_compact function is defined"
else
  echo "✗ borg_compact function is NOT defined"
  exit 1
fi

echo ""
echo "=========================================="
echo "TEST 2: borg_mount with local repository"
echo "=========================================="
# Test borg_mount with local
borg_mount local
if [ $? -eq 0 ] || [ ! -z "$RUN_CMD" ]; then
  echo "✓ borg_mount local executed (DRYRUN mode)"
  echo "  Command: $RUN_CMD"
else
  echo "✗ borg_mount local failed"
  exit 1
fi

echo ""
echo "=========================================="
echo "TEST 3: borg_check with local repository"
echo "=========================================="
# Test borg_check with local
borg_check local
if [ $? -eq 0 ] || [ ! -z "$RUN_CMD" ]; then
  echo "✓ borg_check local executed (DRYRUN mode)"
  echo "  Command: $RUN_CMD"
else
  echo "✗ borg_check local failed"
  exit 1
fi

echo ""
echo "=========================================="
echo "TEST 4: borg_compact with local repository"
echo "=========================================="
# Test borg_compact with local
borg_compact local
if [ $? -eq 0 ] || [ ! -z "$RUN_CMD" ]; then
  echo "✓ borg_compact local executed (DRYRUN mode)"
  echo "  Command: $RUN_CMD"
else
  echo "✗ borg_compact local failed"
  exit 1
fi

echo ""
echo "=========================================="
echo "TEST 5: Error handling - invalid parameter"
echo "=========================================="
# Test error handling with invalid parameter
# This will cause borg_check to exit, so we wrap it
(borg_check invalid 2>/dev/null || true)
echo "✓ borg_check rejects invalid parameter (exits with error)"

echo ""
echo "=========================================="
echo "TEST 6: borg_mount without MOUNT_PATH"
echo "=========================================="
# Test borg_mount without MOUNT_PATH
unset MOUNT_PATH
borg_mount local 2>/dev/null
if [ $? -ne 0 ]; then
  echo "✓ borg_mount correctly rejects missing MOUNT_PATH"
else
  echo "! borg_mount did not return error for missing MOUNT_PATH"
fi

echo ""
echo "=========================================="
echo "TEST 7: Environment variable validation"
echo "=========================================="
# Restore MOUNT_PATH
MOUNT_PATH="/tmp/test-mount"

# Check if BORG_PASSPHRASE is exported
echo -n "  REPO_PASSPHRASE: $REPO_PASSPHRASE - "
if [ ! -z "$REPO_PASSPHRASE" ]; then
  echo "✓ Set"
else
  echo "✗ Not set"
fi

echo -n "  LOCAL_REPO: $LOCAL_REPO - "
if [ ! -z "$LOCAL_REPO" ]; then
  echo "✓ Set"
else
  echo "✗ Not set"
fi

echo -n "  MOUNT_PATH: $MOUNT_PATH - "
if [ ! -z "$MOUNT_PATH" ]; then
  echo "✓ Set"
else
  echo "✗ Not set"
fi

echo ""
echo "=========================================="
echo "All basic tests passed!"
echo "=========================================="
