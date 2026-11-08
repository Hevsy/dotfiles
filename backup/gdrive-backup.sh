#!/usr/bin/env bash
# Secondary two-way sync: keeps non-application-data dirs (Documents,
# Pictures, Projects, etc - see gdrive-filter.txt for the exact allowlist)
# in sync between $HOME and the root of the "gdrive" remote, in both
# directions. Deliberately excludes .config/.local/.cache/.ssh/etc - those
# are either managed by this dotfiles repo already, or pure app state,
# neither of which belongs in a "my files" style sync.
#
# `rclone bisync`, not `sync`: a change made in the Drive web UI (edit,
# add, delete) propagates down to the local machine on the next run, same
# as a local change propagates up - true two-way sync, not a one-way
# mirror. See MIGRATION.md for the history of why this replaced the
# earlier one-way `rclone sync` into a "Backup" subfolder, and for the
# conflict-resolution/safety-check behavior to be aware of.
#
# One-time setup (not scripted - needs an interactive browser for Google's
# OAuth flow): run `rclone config`, create a remote named exactly "gdrive"
# pointing at Google Drive, then run `rclone bisync "$HOME" gdrive:
# --filters-file gdrive-filter.txt --resync` once by hand to establish the
# baseline before this script's unattended (no --resync) runs begin.
#
# Run automatically every 30 min by the gdrive-backup.timer systemd user
# unit (see ../.config/systemd/user/gdrive-backup.{service,timer}).
#
# No --log-file: rclone's own log lines go to stdout/stderr, which the
# oneshot service lets systemd capture into the user journal - size-capped
# and rotated by journald already, so there's no separate log file to grow
# forever or rotate by hand. Check recent runs with:
#   journalctl --user -u gdrive-backup --since -1d
set -euo pipefail

# Non-interactive invocation (systemd) doesn't source .zshrc/.bashrc, so
# make sure the shared Homebrew install (where rclone lives) is on PATH.
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rclone bisync "$HOME" gdrive: \
  --filters-file "$SCRIPT_DIR/gdrive-filter.txt" \
  --log-level INFO
