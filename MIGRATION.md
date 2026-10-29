# Migration: WSL (sago@LAPTOP-*) -> native Ubuntu + Fedora distrobox

## Pre-flight check

Before committing to Ubuntu 26.04 on the host, confirm JumpCloud, Akamai
Guardicore, and Rapid7 agents support it. If any lag behind, fall back to
24.04 LTS - nothing else in this plan changes, only the Ghostty install
path (see below) switches from the native apt package to the community
installer.

## Strategy

- **Host (Ubuntu)**: minimal OS packages, but still gets full console QOL
  (zsh/tmux/neovim) for maintenance work, via the same dotfiles + shared
  Homebrew install described below. Easy to reinstall/upgrade since it
  holds almost no state of its own.
- **Container ("dev", Fedora distrobox)**: the main dev environment -
  cloud/k8s CLIs, IaC tooling, same shell/editor setup. Defined
  declaratively in `distrobox/distrobox.ini` so it can be rebuilt from
  scratch at any time (`distrobox rm dev && distrobox assemble create -f
  distrobox.ini`), e.g. when bumping the Fedora base image.
- **$HOME is shared** between host and container (distrobox's default -
  and *only* $HOME, not the rest of the host filesystem). That means
  dotfiles, SSH keys, AWS/kube config, docker auth, and - see below -
  Homebrew itself, are restored **once**, not duplicated per environment.
- **One shared Homebrew install, one curated `Brewfile`.** No raw
  `apt-mark`/`brew bundle dump` from the old box (full of one-off/forgotten
  packages), and no per-tool vendor curl installers either. See below.

## Shared Homebrew (the actual trick here)

Homebrew's standard Linux install path is `/home/linuxbrew/.linuxbrew`,
which is **outside** `$HOME` and therefore *not* visible inside the
container by default. The fix: install it to a custom prefix **inside**
`$HOME` instead - `~/.homebrew` (an officially supported install method:
`git clone https://github.com/Homebrew/brew ~/.homebrew`). Since that's
inside the shared home, the host and the container see the literal same
files - one Cellar, one `brew update`, used by both.

This is safe for our purposes because Homebrew's Linux bottles are
prebuilt against an old/portable glibc baseline by design (that's the
whole premise of "Linuxbrew" working across distros in the first place) -
fine for the CLI-only tool list below. It would be a bad fit for anything
needing deep OS/GUI integration, which is exactly why GUI apps go through
flatpak instead (see `host-packages.txt`) and terminal emulators get
native packaging (see Ghostty below) rather than a brew formula.

- `Brewfile` (repo root) - the single curated CLI tool list. Run with
  `brew bundle --file=~/dotfiles/Brewfile` on the host **and** inside the
  container - same command, same result, since it's the same files.
- `distrobox/packages-dnf.txt` / `distrobox/host-packages.txt` now only
  carry the OS-level bootstrap packages Homebrew itself needs (build
  tools, curl, git, etc.) plus a handful of things that have to stay
  system packages (podman client in the container, podman/distrobox/
  flatpak/ghostty on the host). These lists are small and stable - no
  curation problem, nothing to mine from shell history for.
- To sanity-check the `Brewfile` contents against actual usage before
  finalizing it further, mine history on the old box:
  `cat ~/.*_history | awk '{print $1}' | sort | uniq -c | sort -rn | head -100`

## Repo layout added for this migration

```
dotfiles/
  Brewfile              # shared CLI tool list - see above
  .gitconfig            # credential helper now uses `gh` from PATH, not a
                         # hardcoded /home/linuxbrew/... path
  .ssh/config           # host aliases only - keys are NOT in this repo
  .p10k.zsh
  .tofurc
  .selected_editor
  .local/bin/dev-shell   # Ghostty's "command" target - drops into the dev container
  .zshrc / .bashrc      # WSL-specific hardcoded paths removed/guarded (see below)
  distrobox/
    distrobox.ini         # container definition (podman socket share, OS packages)
    packages-dnf.txt       # minimal dnf bootstrap list (homebrew deps + podman client)
    host-packages.txt      # minimal host (Ubuntu) package list
    bootstrap-host.sh       # run once on the fresh Ubuntu host
    post-create.sh          # run once inside the container after creation
```

## Fixes already applied to existing dotfiles

WSL/old-host-specific breakage found and fixed in `.zshrc`/`.bashrc`:

- Removed `/mnt/c/Windows/...` PATH entries (WSL Windows interop, N/A on bare metal).
- `.gitconfig` credential helper hardcoded `/home/linuxbrew/.linuxbrew/bin/gh`
  -> now just `gh` (resolved via PATH, works regardless of install method).
- `brew shellenv` calls now point at the shared `~/.homebrew` prefix (see
  above) instead of the old `/home/linuxbrew/.linuxbrew` path, still
  guarded with `-x` so they're harmless no-ops before Homebrew exists.
- `aws_completer` completion call guarded with `command -v` instead of a
  hardcoded linuxbrew path - resolves correctly once the Brewfile's
  `awscli` formula is installed.
- `tofu`/`terraform` completion hooks pointed at a **hardcoded tenv version**
  (`.tenv/OpenTofu/1.9.3/tofu`, and a *different stale* `1.9.1` in `.bashrc`)
  which breaks every time tenv switches versions. Now resolved dynamically
  via `command -v tofu` / `command -v terraform`.
- `DENO_INSTALL` pointed at `/home/paul-rdc/.deno` - a leftover path from a
  different machine/user that doesn't exist. Fixed to `$HOME/.deno`.
- Removed a dead `/home/linuxbrew/.linuxbrew/opt/mysql@8.0/bin` PATH entry
  tied to the old brew location (mysql isn't in the curated `Brewfile`;
  add it there if still needed).

Not changed, but worth a look when you're settled in:
- `.zshrc` aliases `rg='source ranger ranger'` - this shadows ripgrep's `rg`
  with the `ranger` file manager; `rgr` is the alias that actually runs
  ripgrep. Probably intentional, but worth confirming.
- `alias od='onedrive_gui'` - only relevant if you still use an OneDrive
  sync client on Linux.
- `alias update="sudo apt update && sudo apt upgrade -y && brew update && brew upgrade"`
  is host-centric (apt); inside the container you'd want the dnf
  equivalent - not changed since it's a minor convenience alias, not a
  correctness issue.

## Terminal setup

- **Host maintenance console**: the distro's stock terminal app. Zero
  setup, used rarely (podman/distrobox issues, host package upgrades). It
  already gets full zsh/tmux/neovim QOL since the host runs the same
  dotfiles + shared Homebrew as the container.
- **Main work terminal**: Ghostty, configured with its `command` setting
  pointed at `~/.local/bin/dev-shell`, which just `exec`s
  `distrobox enter dev`. Keeps the terminal config decoupled from
  distrobox specifics.
- **Ghostty install** (version-dependent, handled automatically by
  `bootstrap-host.sh`):
  - Ubuntu 26.04+: native `apt install ghostty`.
  - Older LTS: community installer from
    [mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu).
- **Flatpak**: `bootstrap-host.sh` installs `flatpak` and adds the Flathub
  remote once. All other GUI apps go through flatpak; terminal emulators
  (Ghostty/Alacritty) are the deliberate exception since neither has an
  official flatpak - native packages/installers instead, no AppImage
  actually needed for either on current Ubuntu.
- Note: the existing `.zshrc` auto-`tmux attach -s main` behavior fires
  independently on the host and inside the container (separate process
  namespaces) - two unrelated "main" sessions, one per environment.
  Expected, not a bug.

## Step-by-step

### 1. On the old WSL box

1. Finish reviewing/pushing the dotfiles repo (this commit).
2. Make sure every project directory is actually pushed - these were
   found to be loose collections of repos, not single ones; check each
   subfolder individually before wiping anything:
   `Projects/` (contains many independent repos, e.g. `artifacts_*`, `opscli`),
   `devops-book-pp-code/`, `ODIN/`, `workfx-zbi4-backup/`.
3. Build the secrets bundle (encrypt it - see below):
   - `~/.ssh/` - keep only live keys: `id_ed25519*`, `pp_rdc*`, `sg-rdc-ed25519*`
     (not `-v2`/`-old`/`.bak` unless still in use), `jenkins.pem`,
     `ray-autoscaler_ssh_key*`. Drop `known_hosts.bak`, `known_hosts.old`.
   - `~/.aws/config` (keep) - drop `~/.aws/sso/cache`, `~/.aws/cli/cache`,
     `~/.aws/default.cred` (re-auth instead of carrying cached tokens).
   - `~/.lacework.toml`, `wguard_*.conf`.
   - Tighten permissions while you're at it - several key files currently
     have loose `rw--w--w-` perms: `chmod 600 ~/.ssh/id_* ~/.ssh/pp_rdc* ~/.ssh/sg-rdc* ~/.ssh/ray-autoscaler_ssh_key`.
   - Encrypt: `tar czf - -C ~ .ssh .aws/config .lacework.toml wguard_pparinov_aunsw.conf | gpg -c -o secrets.tar.gz.gpg`
4. Tar the bulk project/data folders you want to keep, excluding caches and
   build artifacts:
   ```
   tar --exclude='.cache' --exclude='.npm' --exclude='.bun' \
       --exclude='*.zcompdump*' --exclude='*_history' \
       --exclude='.kube/cache' --exclude='.aws/sso/cache' --exclude='.aws/cli/cache' \
       --exclude='efs-utils/src/proxy/target' \
       -czf ~/home-backup.tar.gz -C ~ Projects devops-book devops-book-pp-code \
       medusa ODIN efs-utils go scripts tmp workfx-zbi4-backup
   ```
5. Copy `secrets.tar.gz.gpg` and `home-backup.tar.gz` off-box (external
   drive / cloud storage you control - not into the dotfiles git repo).

### 2. On the fresh Ubuntu install

```
sudo apt update && sudo apt install -y git
git clone https://github.com/Hevsy/dotfiles.git ~/dotfiles
cd ~/dotfiles/distrobox
./bootstrap-host.sh
```

This installs podman/distrobox/flatpak/Ghostty on the host, sets up the
shared `~/.homebrew` install and runs `brew bundle`, stows the dotfiles and
installs oh-my-zsh on the host itself (so the stock terminal is immediately
usable for maintenance), then assembles the `dev` Fedora container from
`distrobox.ini`.

### 3. Enter the container and finish setup

```
distrobox enter dev
bash ~/dotfiles/distrobox/post-create.sh
```

Stows the dotfiles again inside the container (same repo, same symlinks),
confirms/installs the shared Homebrew tool set, and installs oh-my-zsh and
krew plugins.

### 4. Restore secrets and data

```
gpg -d ~/secrets.tar.gz.gpg | tar xzf - -C ~
chmod 600 ~/.ssh/id_* ~/.ssh/pp_rdc* ~/.ssh/sg-rdc* ~/.ssh/ray-autoscaler_ssh_key
tar xzf ~/home-backup.tar.gz -C ~
```

### 5. Fix environment-specific config that can't just be copied

These broke on the move from WSL and need to be redone rather than restored:

- **`.azure`** was a symlink to `/mnt/c/Users/.../.azure` (Windows) - gone.
  Just `az login` again; a real `~/.azure` will be created.
- **`.kube/config`** - don't copy the cached config; regenerate per cluster:
  `aws eks update-kubeconfig --name <cluster> --region <region> --profile <profile>`
  (there are ~18 cluster contexts on the old box - script this if it's a lot).
- **`.aws` SSO cache** - don't copy; `aws sso login --sso-session rdc` (the
  `logmein` alias) re-populates it.
- **`.docker/config.json`** - had `"credsStore": "desktop.exe"` (Docker
  Desktop for Windows integration). The Brewfile installs
  `docker-credential-helper-ecr` (provides `docker-credential-ecr-login`);
  update the file to:
  ```json
  { "credHelpers": { "<account>.dkr.ecr.<region>.amazonaws.com": "ecr-login" } }
  ```
  for each ECR registry you use, and drop the `credsStore` line.
- Set zsh as the default shell, on the host and in the container:
  `chsh -s "$(command -v zsh)"`.
- Point Ghostty's `command` config at `~/.local/bin/dev-shell`.

### 6. Rebuilding/upgrading the container later

```
distrobox stop dev && distrobox rm dev
cd ~/dotfiles/distrobox && ./bootstrap-host.sh   # bumps the Fedora image too if you edit distrobox.ini
distrobox enter dev && bash ~/dotfiles/distrobox/post-create.sh
```

$HOME (and everything in it - dotfiles, keys, projects, `~/.homebrew`) is
untouched by this, since all of that lives on the host side of the shared
home mount.

## Explicitly excluded from backup (regenerate/reinstall instead of copying)

- `.cache/`, `.npm`, `.bun`, `snap/`
- `.*_history`, `.zcompdump*` (several stale ones from old hostnames)
- `*.bak`, `*.old`, `known_hosts.bak`, `known_hosts.old`
- `.kube/cache`, `.aws/sso/cache`, `.aws/cli/cache`
- `.vscode-server`, `.vscode-remote-containers` (WSL Remote-* artifacts, N/A natively)
- build artifacts, e.g. `efs-utils/src/proxy/target`
