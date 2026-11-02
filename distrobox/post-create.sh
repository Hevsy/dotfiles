#!/usr/bin/env bash
# Run ONCE inside the "dev" distrobox after it's first created:
#   distrobox enter dev
#   bash ~/dotfiles/distrobox/post-create.sh
#
# Installs the container's own Homebrew (standard /home/linuxbrew/.linuxbrew
# prefix, inside the container rootfs - NOT the host's), then the full
# Brewfile tool set, stows dotfiles, and installs oh-my-zsh. Anything brew
# can't cover (krew plugins, nvim/mason bootstrap) is handled below.
#
# The container's brew is wiped by `distrobox rm dev`; re-running this script
# after a rebuild reinstalls it.
set -euo pipefail

if [ ! -f /run/.containerenv ] && [ ! -f /.dockerenv ]; then
  echo "This script is for the dev container - run bootstrap-host.sh on the host." >&2
  exit 1
fi

BREW=/home/linuxbrew/.linuxbrew/bin/brew

# $HOME is shared with the host, so keep the container brew's download cache
# and logs inside the container rootfs. Sharing them with the host install
# invites cross-distro cache/lock confusion.
export HOMEBREW_CACHE=/home/linuxbrew/.cache
export HOMEBREW_LOGS=/home/linuxbrew/.logs
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1

echo "==> Installing Homebrew (container-local, standard prefix)"
if [ ! -x "$BREW" ]; then
  sudo rm -rf /home/linuxbrew/.linuxbrew
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW" shellenv)"

echo "==> Installing the full dev tool set (Brewfile)"
# Before stowing: stow itself comes from this bundle and doesn't exist in a
# fresh container.
brew bundle --file="$HOME/dotfiles/Brewfile"

echo "==> Stowing dotfiles"
cd "$HOME/dotfiles"
if [ "${ALLOW_DIRTY:-0}" != 1 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "dotfiles repo has uncommitted changes - commit/stash, or rerun with ALLOW_DIRTY=1" >&2
  exit 1
fi
# --adopt lets stow claim real files that dnf/brew/distrobox already created
# at these paths instead of erroring out on every conflict (overwrites the
# repo's tracked content with the real file's content to do so); the
# `git checkout` right after discards that and restores the curated version
# - net effect: every target becomes a symlink, with OUR content.
stow --no-folding --adopt -t ~ .
git checkout -- .

echo "==> Installing oh-my-zsh (shared \$HOME: usually already present)"
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> krew plugins"
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl krew install neat ctx ns

echo "==> Bootstrapping Neovim plugins + Mason (LSPs/linters/DAPs)"
# Mason installs OS/arch-specific binaries under ~/.local/share/nvim/mason -
# never portable across machines, so always force a clean headless bootstrap
# here instead of trusting anything carried over from a backup/restore. See
# MIGRATION.md for why ~/.local/share/nvim is excluded from the backup tarball.
nvim --headless "+Lazy! sync" "+MasonToolsUpdate" +qa || true

cat <<'EOF'

Done. Still TODO manually:
  - chsh -s "$(command -v zsh)"          (set zsh as the container's default shell)
  - aws sso login --sso-session rdc      (re-auth, don't copy cached SSO tokens)
  - aws eks update-kubeconfig --name ... (regenerate kube contexts per cluster)
  - point ~/.docker/config.json credsStore at ecr-login (docker-credential-helper-ecr,
    installed via Brewfile, provides docker-credential-ecr-login) instead of desktop.exe
  - restore ~/.ssh keys from the secrets bundle, then: chmod 600 ~/.ssh/id_* ~/.ssh/pp_rdc* ~/.ssh/sg-rdc*
See ~/dotfiles/MIGRATION.md for details.
EOF
