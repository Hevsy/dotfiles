#!/usr/bin/env bash
# Run ONCE inside the "dev" distrobox after it's first created:
#   distrobox enter dev
#   bash ~/dotfiles/distrobox/post-create.sh
#
# Installs oh-my-zsh, stows dotfiles, and installs the shared Homebrew tool
# set (~/.homebrew, see ../Brewfile - already present if bootstrap-host.sh
# ran first, since it lives inside the shared $HOME). Anything brew can't
# cover (ECR docker credential config, krew plugins) is handled below.
set -euo pipefail

echo "==> Stowing dotfiles"
cd ~/dotfiles
stow -t ~ .

echo "==> Installing Homebrew to ~/.homebrew if not already present (shared with the host)"
if [ ! -d "$HOME/.homebrew" ]; then
  git clone https://github.com/Homebrew/brew "$HOME/.homebrew"
fi
eval "$("$HOME/.homebrew/bin/brew" shellenv)"
brew bundle --file="$HOME/dotfiles/Brewfile"

echo "==> Installing oh-my-zsh (unattended, keeps existing .zshrc)"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> krew plugins"
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl krew install neat ctx ns

cat <<'EOF'

Done. Still TODO manually:
  - chsh -s "$(command -v zsh)"          (set zsh as the container's default shell)
  - aws sso login --sso-session rdc      (re-auth, don't copy cached SSO tokens)
  - az login                             (the old .azure WSL symlink is gone)
  - aws eks update-kubeconfig --name ... (regenerate kube contexts per cluster)
  - point ~/.docker/config.json credsStore at ecr-login (docker-credential-helper-ecr,
    installed via Brewfile, provides docker-credential-ecr-login) instead of desktop.exe
  - restore ~/.ssh keys from the secrets bundle, then: chmod 600 ~/.ssh/id_* ~/.ssh/pp_rdc* ~/.ssh/sg-rdc*
See ~/dotfiles/MIGRATION.md for details.
EOF
