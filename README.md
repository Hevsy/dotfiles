### Fresh machine

```bash
git clone https://github.com/Hevsy/dotfiles.git ~/dotfiles
cd ~/dotfiles/distrobox
./bootstrap-host.sh
```

Host-only after that: `cd ~/dotfiles && stow --no-folding -t ~ .` if you ever
want to re-link manually. `--no-folding` is required so per-directory
exclusions in `.stow-local-ignore` (notably `.config/opencode`) are applied
instead of a whole directory being symlinked. Host tools come from
`Brewfile.host`.

Then create/finish the dev container:

```bash
distrobox enter dev
bash ~/dotfiles/distrobox/post-create.sh
```

Container tools come from the full `Brewfile` and the container's own
Homebrew at `/home/linuxbrew/.linuxbrew`.

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
