### Installation:
From inside the dotfiles directory:
```bash
stow -t ~ .
```

### Homebrew installation:
```bash
# Leaving a machine
brew leaves > leaves.txt

# Fresh installation
xargs brew install < leaves.txt
```

### Fresh machine / distro migration

See [MIGRATION.md](MIGRATION.md) for the full WSL -> Ubuntu host + Fedora
distrobox migration strategy, including the `distrobox/` bootstrap scripts,
curated package lists, and secrets handling.
