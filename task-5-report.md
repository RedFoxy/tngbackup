# Task 5 - Security Fix: Environment Variable Cleanup

## Fix Round 1/5

### Issue
Critical security vulnerability: BORG_PASSPHRASE, BORG_REPO, and BORG_ENCRYPTION environment variables were being exported in borg_* functions (borg_init, borg_create, borg_info, borg_check, borg_compact, borg_prune) but cleanup statements were scattered and unreliable. Variables remained exposed in the environment after function execution.

### Root Cause
- Environment variables set via `export` in borg_* functions
- Cleanup statements (`unset`) were placed at the end of functions without trap-based cleanup guarantee
- No centralized cleanup mechanism on script exit

### Solution Implemented
1. **Added cleanup handler to functions.sh**
   - Created `cleanup()` function that unsets: BORG_PASSPHRASE, BORG_REPO, BORG_ENCRYPTION, BORG_RSH
   - Installed trap on EXIT signal to ensure cleanup runs on script termination

2. **Removed unreliable cleanup from borg_* functions**
   - Removed `unset` statements from:
     - borg_init.sh
     - borg_create.sh
     - borg_info.sh
     - borg_check.sh
     - borg_compact.sh
     - borg_prune.sh
   - Removed redundant unsets from main script (tngbackup2.sh lines 482-484)

3. **Centralized cleanup mechanism**
   - EXIT trap ensures cleanup() runs when script exits (normally or via error)
   - Variables are reliably cleaned up regardless of function return paths

### Files Modified
- `v2/classi/functions.sh` - Added cleanup handler and trap
- `v2/classi/borg_init.sh` - Removed unset statements
- `v2/classi/borg_create.sh` - Removed unset statements
- `v2/classi/borg_info.sh` - Removed unset statements
- `v2/classi/borg_check.sh` - Removed unset statements
- `v2/classi/borg_compact.sh` - Removed unset statements
- `v2/classi/borg_prune.sh` - Removed unset statements
- `v2/tngbackup2.sh` - Removed redundant unset statements

### Testing
Verification test created and passed:
```bash
test-env-cleanup.sh
✓ Before cleanup: BORG_PASSPHRASE set
✓ After cleanup: BORG_PASSPHRASE empty
✓ All variables successfully cleared
```

### Security Impact
- **Before**: Credentials remained in shell environment after execution
- **After**: All sensitive environment variables are cleaned up on script exit via trap handler
- Credentials are now properly isolated and cleaned up regardless of script exit path (normal completion, error, or signal)

### Commit
- Commit: 3b8ebc1
- Message: "fix: move environment variable cleanup to trap handler"

### Next Steps
- Fix Round 2: Additional environment variable exposure checks
- Fix Round 3: Audit command line history/logging
- Fix Round 4: Review temporary file handling
- Fix Round 5: Final security validation
