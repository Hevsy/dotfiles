# Shared CLI tool list - installed to ~/.homebrew, which lives inside
# $HOME and is therefore shared automatically between the Ubuntu host and
# the Fedora "dev" distrobox (distrobox only shares $HOME, nothing else -
# see MIGRATION.md for why a shared Homebrew install is safe here).
#
# Run with: brew bundle --file=~/dotfiles/Brewfile
# Same command, same result, on the host and inside the container.
#
# Not listed here: GUI apps (flatpak - see distrobox/host-packages.txt) and
# terminal emulators (native packaging - see bootstrap-host.sh), since both
# need OS-level integration that Homebrew on Linux doesn't provide.

# --- shell & terminal ---
brew "zsh"
brew "tmux"
brew "fzf"
brew "ripgrep"
brew "bat"
brew "fd"
brew "tree"
brew "direnv"

# --- editor (neovim is primary editor - config in .config/nvim) ---
# known-good: v0.11.6 (WSL, Oct 2026) - LSPs/linters confirmed working against
# this version + the pinned .config/nvim/lazy-lock.json. If an upgrade breaks
# LSPs/linters, see MIGRATION.md for how to reinstall this exact version.
brew "neovim"

# --- vcs ---
brew "git"
brew "gh"
brew "lazygit"
brew "stow"

# --- cloud / k8s / IaC ---
brew "awscli"
brew "kubernetes-cli"
brew "helm"
brew "krew"
brew "tenv"
brew "docker-credential-helper-ecr"
brew "k9s"

# --- languages / runtimes ---
brew "go"
brew "rust"
brew "uv"

# --- misc cli ---
brew "jq"
brew "htop"
brew "ncdu"
brew "mc"
brew "ranger"
brew "opencode"
