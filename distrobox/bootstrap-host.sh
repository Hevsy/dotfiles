#!/usr/bin/env bash
# Run once on a fresh Ubuntu host. Sets up the host for maintenance work
# (zsh/tmux/neovim via a shared Homebrew install, Ghostty as the main
# terminal) and assembles the "dev" Fedora distrobox for everything else.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd .. && pwd)"

echo "==> Installing host packages (podman, distrobox, flatpak, homebrew build deps)"
sudo apt update
xargs -a host-packages.txt sudo apt install -y

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

echo "==> Installing Homebrew to ~/.homebrew (shared with the dev container via \$HOME)"
if [ ! -d "$HOME/.homebrew" ]; then
  git clone https://github.com/Homebrew/brew "$HOME/.homebrew"
fi
eval "$("$HOME/.homebrew/bin/brew" shellenv)"
brew bundle --file="$DOTFILES_DIR/Brewfile"

echo "==> Stowing dotfiles on the host"
(cd "$DOTFILES_DIR" && stow -t ~ .)

echo "==> Installing oh-my-zsh on the host (unattended, keeps existing .zshrc)"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

export HOST_UID
HOST_UID="$(id -u)"

export EXTRA_PACKAGES
EXTRA_PACKAGES="$(grep -vE '^\s*#|^\s*$' packages-dnf.txt | tr '\n' ' ')"

echo "==> Assembling the dev container"
distrobox assemble create -f distrobox.ini

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
