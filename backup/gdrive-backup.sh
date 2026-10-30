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
set -euo pipefail

# Non-interactive invocation (systemd) doesn't source .zshrc/.bashrc, so
# make sure the shared Homebrew install (where rclone lives) is on PATH.
eval "$("$HOME/.homebrew/bin/brew" shellenv)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/.local/state/gdrive-backup.log"
mkdir -p "$(dirname "$LOG_FILE")"

rclone sync "$HOME" "gdrive:Backup" \
  --filter-from "$SCRIPT_DIR/gdrive-filter.txt" \
  --fast-list \
  --log-file "$LOG_FILE" --log-level INFO
