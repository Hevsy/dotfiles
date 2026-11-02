#!/usr/bin/env bash
# Run once on a fresh Ubuntu host. Sets up the host for maintenance work
# (zsh/tmux/neovim via a host-only Homebrew install, Ghostty as the main
# terminal) and assembles the "dev" Fedora distrobox for everything else.
#
# Homebrew lives at the standard /home/linuxbrew/.linuxbrew on the host. The
# container has its own independent install at the same path (inside the
# container's rootfs) - see post-create.sh. Never bind-mount /home/linuxbrew
# into the container: the separation is deliberate, so host and container
# never share cross-distro bottles.
set -euo pipefail

if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
  echo "This script is for the host - run post-create.sh inside the container." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd .. && pwd)"
BREW=/home/linuxbrew/.linuxbrew/bin/brew

echo "==> Installing host packages (podman, distrobox, flatpak, homebrew build deps)"
sudo apt update
grep -vE '^\s*#|^\s*$' host-packages.txt | xargs sudo apt install -y

echo "==> Adding the Flathub remote (for GUI apps - see MIGRATION.md)"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "==> Installing Ghostty"
. /etc/os-release
if [ "${VERSION_ID%%.*}" -ge 26 ] 2>/dev/null; then
  sudo apt install -y ghostty
else
  echo "Ubuntu < 26.04 detected - using the community ghostty-ubuntu installer"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
fi

echo "==> Enabling the rootless podman socket (needed for container sharing)"
systemctl --user enable --now podman.socket

echo "==> Installing Homebrew to /home/linuxbrew/.linuxbrew (standard prefix)"
if [ ! -x "$BREW" ]; then
  sudo rm -rf /home/linuxbrew/.linuxbrew
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW" shellenv)"
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1

echo "==> Installing host tool set (Brewfile.host)"
brew bundle --file="$DOTFILES_DIR/Brewfile.host"

echo "==> Stowing dotfiles on the host"
# --adopt lets stow claim real files that installers above already created
# (Ghostty, Homebrew, etc.) instead of erroring out on every conflict; it
# does so by overwriting the repo's tracked content with whatever that real
# file contained, so `git checkout` immediately after restores the curated
# version - net effect: every target becomes a symlink, with OUR content.
# Abort on a dirty tree so that checkout can't discard uncommitted work.
cd "$DOTFILES_DIR"
if [ "${ALLOW_DIRTY:-0}" != 1 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "dotfiles repo has uncommitted changes - commit/stash, or rerun with ALLOW_DIRTY=1" >&2
  exit 1
fi
# Drop stale links left by older stow runs for paths now in .stow-local-ignore.
for p in Brewfile Brewfile.host MIGRATION.md README.md backup distrobox; do
  [ -L "$HOME/$p" ] && rm -f "$HOME/$p"
done
stow --no-folding --adopt -t ~ .
git checkout -- .

echo "==> Installing oh-my-zsh on the host (unattended, keeps existing .zshrc)"
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  echo "oh-my-zsh install failed - .zshrc will not start" >&2
  exit 1
fi

echo "==> Installing tmux plugins (shared \$HOME, so the container reuses them)"
# Deterministic clone instead of `tpm install_plugins`, which needs a live
# tmux server; the plugin set is fixed and small. catppuccin v2 must be
# cloned under its TPM path and sourced from .tmux.conf - @plugin alone
# installs it but never loads it.
TPM="$HOME/.tmux/plugins"
tmux_clone() {
  local dest="$TPM/$2"
  [ -d "$dest" ] || { mkdir -p "$(dirname "$dest")"; git clone --depth=1 "$1" "$dest"; }
}
tmux_clone https://github.com/tmux-plugins/tpm             tpm
tmux_clone https://github.com/tmux-plugins/tmux-sensible  tmux-sensible
tmux_clone https://github.com/tmux-plugins/tmux-yank      tmux-yank
tmux_clone https://github.com/tmux-plugins/tmux-resurrect tmux-resurrect
tmux_clone https://github.com/tmux-plugins/tmux-continuum tmux-continuum
tmux_clone https://github.com/omerxx/tmux-sessionx        tmux-sessionx
tmux_clone https://github.com/catppuccin/tmux             catppuccin/tmux

echo "==> Google Drive secondary backup (rclone)"
if "$BREW" list rclone >/dev/null 2>&1 && rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
  systemctl --user enable --now gdrive-backup.timer
else
  cat <<'EOF'
No 'gdrive' rclone remote configured yet - this needs an interactive
browser for Google's OAuth flow, so it's not scripted. Once done, enable
the timer:
  rclone config          # create a remote named exactly "gdrive" (Google Drive)
  systemctl --user enable --now gdrive-backup.timer
See ~/dotfiles/backup/gdrive-backup.sh and MIGRATION.md for details.
EOF
fi

export HOST_UID
HOST_UID="$(id -u)"

export EXTRA_PACKAGES
EXTRA_PACKAGES="$(grep -vE '^\s*#|^\s*$' packages-dnf.txt | tr '\n' ' ')"

echo "==> Assembling the dev container"
if distrobox list 2>/dev/null | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -qx dev; then
  echo "container 'dev' already exists - skipping assemble"
else
  distrobox assemble create -f distrobox.ini
fi

cat <<EOF

Host is ready for maintenance work: zsh/tmux/neovim/brew all usable right
here in the stock terminal (chsh -s "\$(command -v zsh)" if you want it as
the default shell).

Container created. Next steps:
  distrobox enter dev
  bash ~/dotfiles/distrobox/post-create.sh

Point Ghostty's "command" setting at ~/.local/bin/dev-shell to make it
drop straight into the dev container.

See ~/dotfiles/MIGRATION.md for the full walkthrough.
EOF
