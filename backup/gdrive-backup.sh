#!/usr/bin/env bash
# Secondary backup: mirrors non-application-data dirs (Documents, Pictures,
# Projects, etc - see gdrive-filter.txt for the exact allowlist) to Google
# Drive. Deliberately excludes .config/.local/.cache/.ssh/etc - those are
# either managed by this dotfiles repo already, or pure app state, neither
# of which belongs in a "my files" style backup.
#
# True mirror (`rclone sync`, not `copy`): deleting a file locally deletes
# it from Drive on the next run too. Chosen deliberately over the safer
# `copy` (never deletes remotely) - see MIGRATION.md for the tradeoff.
#
# One-time setup (not scripted - needs an interactive browser for Google's
# OAuth flow): run `rclone config`, create a remote named exactly "gdrive"
# pointing at Google Drive. This script syncs into a "Backup" folder inside
# that remote, created automatically on first run if it doesn't exist.
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

rclone sync "$HOME" "gdrive:Backup" \
  --filter-from "$SCRIPT_DIR/gdrive-filter.txt" \
  --fast-list \
  --log-level INFO
