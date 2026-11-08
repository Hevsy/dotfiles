# Migration: WSL (sago@LAPTOP-*) -> native Ubuntu + Fedora distrobox

## Pre-flight check

Endpoint agent compatibility, checked against each vendor's docs:

| Agent | Ubuntu 26.04 | Notes |
|---|---|---|
| JumpCloud | ✅ | Supported since the Apr 2026 agent release. |
| Rapid7 Insight Agent | ✅ | Requires agent ≥ 4.1.2. |
| Akamai Guardicore Platform Agent | ❌ | Latest docs (v7.4.0-v7.5.0) only list 22.04/24.04, scoped to "running GNOME desktop environment". |

Guardicore is the blocker. Options, in order of preference:
1. **Fall back to 24.04 LTS** for the host. Zero ambiguity, all three agents
   natively supported. Nothing else in this plan changes - only the Ghostty
   install path (see below) switches from the native apt package to the
   community installer.
2. **26.04 + a dedicated "compliance" distrobox** running Guardicore inside
   an Ubuntu 24.04 toolbox, same trick NixOS users already use for agents
   that don't support their host OS. Distrobox shares the host's PID/net
   namespaces by default (no `--unshare-process`/`--unshare-netns`), so an
   agent inside the container still observes real host activity - it's not
   meaningfully sandboxed away the way a normal container would be.
   Caveats before relying on this:
   - The agent reports "Ubuntu 24.04" to the management console, not the
     true host OS - a visible mismatch if device inventory is ever audited.
   - Guardicore specifically does network *enforcement* (netfilter/iptables
     rules), not just monitoring, which typically needs real privileges
     (`NET_ADMIN`-equivalent) a rootless container doesn't have by default -
     no confirmed precedent found for this working with Guardicore
     specifically (only CrowdStrike/Kolide discussions turned up).
   - Rootless distrobox containers don't auto-survive reboots as a running
     service; needs a host-level systemd user unit to start the compliance
     container (and the agent inside it) on boot/login.
   - "Runs" isn't "approved" - confirm with whoever owns the agent policy
     before relying on this for anything that matters.
3. Check whether Guardicore is even still mandated on this specific device -
   personal/dev laptop policy sometimes differs from the managed fleet.

Confirm with IT/security before finalizing the host OS version.

## Strategy

- **Host (Ubuntu)**: minimal OS packages, plus a maintenance-only console
  QOL (zsh/tmux/neovim) set via its own Homebrew install (`Brewfile.host`).
  Easy to reinstall/upgrade since it holds almost no state of its own.
- **Container ("dev", Fedora distrobox)**: the main dev environment -
  cloud/k8s CLIs, IaC tooling, same shell/editor setup. Defined
  declaratively in `distrobox/distrobox.ini` so it can be rebuilt from
  scratch at any time (`distrobox rm dev && distrobox assemble create -f
  distrobox.ini`), e.g. when bumping the Fedora base image.
- **$HOME is shared** between host and container (distrobox's default -
  and *only* $HOME, not the rest of the host filesystem). That means
  dotfiles, SSH keys, AWS/kube config, docker auth, tmux plugins and
  oh-my-zsh are restored **once**, not duplicated per environment.
- **Two independent Homebrew installs, both at the standard prefix.** No raw
  `apt-mark`/`brew bundle dump` from the old box (full of one-off/forgotten
  packages), and no per-tool vendor curl installers either. See below.

## Homebrew (host and container are deliberately separate)

Homebrew lives at its standard Linux path, `/home/linuxbrew/.linuxbrew`, on
**both** sides:

- **Host**: its own install, tools from `Brewfile.host` (maintenance QoL only).
- **Container**: its own install in the container rootfs, same path, tools
  from the full `Brewfile`.

Same path on both sides means the dotfiles never branch on environment, but
the Cellars are completely independent - the container's
`/home/linuxbrew/.linuxbrew` is not the host's, because distrobox only shares
`$HOME`. This is what makes it safe: bottles are never used across glibc/
distro boundaries, and there is no chance of a Fedora-built binary ending up
on the Ubuntu host (or vice versa).

Rules that keep it that way:

- **Never** add a `volume=` mapping `/home/linuxbrew` into the container.
- The container's brew is wiped by `distrobox rm dev`; re-running
  `post-create.sh` reinstalls it. Expect a slow rebuild.
- Because `$HOME` is shared but the prefix isn't, the container sets
  `HOMEBREW_CACHE=/home/linuxbrew/.cache` and `HOMEBREW_LOGS=/home/linuxbrew/.logs`
  (container-local) so the two installs don't share downloads/locks.
- `Brewfile` (repo root) - full dev tool list, container only. Run with
  `brew bundle --file=~/dotfiles/Brewfile`.
- `Brewfile.host` (repo root) - minimal host list (shell/editor, tmux,
  maintenance tools, rclone). Run with
  `brew bundle --file=~/dotfiles/Brewfile.host`.
- `distrobox/packages-dnf.txt` / `distrobox/host-packages.txt` carry only the
  OS-level bootstrap packages Homebrew itself needs (build tools, curl, git,
  bzip2, patch, etc.) plus things that must stay system packages (podman
  client in the container, podman/distrobox/flatpak on the host). These lists
  are small and stable - no curation problem.
- To sanity-check either Brewfile against actual usage, mine history:
  `cat ~/.*_history | awk '{print $1}' | sort | uniq -c | sort -rn | head -100`

## Repo layout added for this migration

```
dotfiles/
  Brewfile              # full dev-container CLI tool list - see above
  Brewfile.host         # minimal host maintenance tool list - see above
  .stow-local-ignore    # keeps non-stowed files and opencode service.json out of $HOME
  .gitconfig            # credential helper now uses `gh` from PATH, not a
                         # hardcoded /home/linuxbrew/... path
  .gitignore            # excludes .viminfo, zcompdump, opencode service.json - see below
  .ssh/config           # host aliases only - keys are NOT in this repo
  .p10k.zsh
  .tofurc
  .selected_editor
  .tmux.conf            # catppuccin v2 syntax (see Neovim/tmux reproducibility below)
  .local/bin/dev-shell   # Ghostty's "command" target - drops into the dev container
  .zshrc / .bashrc      # WSL-specific hardcoded paths removed/guarded (see below)
  .config/
    nvim/
      lazy-lock.json     # plugin version lockfile - see below
    ghostty/config.ghostty   # prepped now, inert until there's a Ghostty to read it
    opencode/opencode.json, prompts/*.txt   # settings + custom build/plan prompts
    mc/ini, mc/tokyo-night-16M.ini          # prepped now, inert on this box (brew mc not installed yet)
  .local/share/mc/skins/tokyo-night-16M.ini  # actual skin lookup path mc reads from
  .config/systemd/user/
    gdrive-backup.service, gdrive-backup.timer  # see Google Drive backup below
  backup/
    gdrive-backup.sh       # NOT stowed - run via its repo path, like Brewfile/distrobox
    gdrive-filter.txt       # rclone allowlist - see Google Drive backup below
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
- `brew shellenv` calls point at the standard
  `/home/linuxbrew/.linuxbrew` prefix, still guarded with `-x` so they're
  harmless no-ops before Homebrew exists.
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
  ripgrep. That's intentional (`source ranger ranger` is ranger's own
  polyglot wrapper, which cds to the last directory on exit), but worth
  remembering when you want ripgrep.

The OneDrive/Upwind/Azure leftovers from the old Microsoft-stack / BYO-laptop
era are gone: `od`/`onedrive_gui`, `~/.upwindctl/env`, and the `.azure`
symlink had no purpose on the Google-stack laptop. Recreate the Upwind agent
inside the container if it's ever needed again.

Also fixed since the first draft of this doc:
- `alias update=...` is now OS-aware (`dnf` in the Fedora container, `apt` +
  optional `flatpak update` on the Ubuntu host) instead of hardcoded to
  `apt` - same alias name, same `.zshrc`, correct command in both places.
- `.viminfo` had been tracked in this repo since its very first commit -
  that's Vim's cache/history file, not config; grows forever and is
  machine/session-specific. Removed from git, added to the new
  `.gitignore` alongside the `~/.config/opencode` plugin-dev sandbox
  (`node_modules/`, lockfiles - reinstallable, not config).

## Neovim & tmux reproducibility

Lesson learned from the `dell` branch (Bazzite laptop migration, done earlier
using an older copy of these dotfiles): installing "the latest" tmux there
pulled a fresh catppuccin/tmux plugin update alongside it, and that plugin's
v2 API rewrite broke the whole status line. Separately, most Neovim
LSPs/linters failed to start after that migration and were never fixed.
Root causes and the fixes applied here so this migration doesn't repeat them:

- **`.tmux.conf`** now uses catppuccin's v2 syntax (`@catppuccin_flavor`,
  explicit `@catppuccin_window_status_style`, `status-left`/`status-right`
  assembled from `#{E:@catppuccin_status_...}` tokens) - ported from `dell`,
  with `tmux-sessionx` re-added (dropped there, kept here) and the shell path
  fixed to `/home/linuxbrew/.linuxbrew/bin/zsh`. catppuccin v2 is explicitly
  `run` from `~/.tmux/plugins/catppuccin/tmux/catppuccin.tmux` - `@plugin`
  alone only clones it and leaves the status tokens empty.
- **`.config/nvim/lazy-lock.json`** (lazy.nvim's plugin lockfile, pins every
  plugin to an exact commit) is now committed for the first time - using
  **this WSL box's actual lockfile**, not `dell`'s. Diffed the two: every
  single plugin commit differs, and `dell`'s is the lockfile from the
  machine where LSPs/linters never started - i.e. it's the known-*broken*
  state, not a fix. Pinning this box's working versions means a fresh
  `:Lazy sync` on the new machine reproduces what's actually working today,
  instead of grabbing latest HEAD of 30+ plugins (the same category of
  problem that broke tmux above).
- **Mason** (LSP/linter/DAP installer) installs OS/arch-specific compiled
  binaries under `~/.local/share/nvim/mason/` - never portable across a
  WSL->Fedora-distrobox (or Ubuntu->Bazzite) move. This is the suspected real
  cause of `dell`'s LSP/linter failures: an old backup likely carried over
  wrong-arch/wrong-glibc binaries that Neovim found but couldn't execute.
  Fix: `~/.local/share/nvim` and `~/.local/state/nvim` are **excluded from
  the backup tarball** (see below) and `distrobox/post-create.sh` runs a
  forced headless bootstrap (`:Lazy! sync` + `:MasonToolsUpdate`) so
  LSPs/linters are confirmed working *before* Neovim is ever opened
  interactively.
- **Neovim version**: known-good is `v0.11.6` (this WSL box, confirmed
  working against the pinned lockfile above). The `Brewfile` installs
  neovim unpinned for simplicity - if a future `brew upgrade` breaks
  LSPs/linters, the exact old version can be reinstalled via Homebrew's
  historical-formula trick:
  `brew install https://raw.githubusercontent.com/Homebrew/homebrew-core/<old-commit>/Formula/n/neovim.rb`
  (find `<old-commit>` by searching `homebrew-core`'s git log for the
  `neovim` formula around the date it was last known to work).

## Breakages hit on the real Ubuntu 26.04 run

Things the first pass got wrong, now fixed in the scripts above:

- **`xargs -a host-packages.txt sudo apt install` fed comment lines to apt.**
  Unlike the dnf list, the host list was never stripped (`#`, `Minimal`,
  `Ubuntu`... treated as package names). Both lists are now filtered with
  `grep -vE '^\s*#|^\s*$'`.
- **Two Homebrew installs, one of them empty.** A stale `~/.homebrew` from
  the original design plus a bare `git clone` into `/home/linuxbrew/.linuxbrew`
  (no taps, empty Cellar) meant `brew` "worked" but installed nothing. Both
  are now installed with the official installer, at the standard prefix, one
  per environment.
- **`stow` broke after a Homebrew perl upgrade** (`use lib .../perl/5.38.2_1`
  hardcoded in `bin/stow` while perl was 5.44). A `brew reinstall stow` fixes
  it; reinstalling from a fresh prefix avoids it entirely.
- **`post-create.sh` stowed before brew existed**, so `stow` was not found in
  a fresh container. Reordered: brew → bundle → stow.
- **oh-my-zsh was never installed** and its failure was silent, leaving
  `source $ZSH/oh-my-zsh.sh` failing on every zsh start. Now a hard check.
- **tmux had three separate faults**: `default-shell` pointed at the old
  `/home/sago` home, TPM was never installed, and catppuccin v2 was only
  declared as `@plugin` (cloned, never sourced) - so the status line was
  empty. All three are handled by `bootstrap-host.sh` and `.tmux.conf`.
- **opencode rewrites its own config in place**, replacing the stow symlink
  with a real file. It is stowed now, but only re-adopt it from a plain TTY
  with no opencode session running (`stow --no-folding --adopt -t ~ .`, then
  review and commit - do *not* `git checkout` if the live file has the newer
  config). Its machine-local `service.json` is excluded in
  `.stow-local-ignore` and gitignored, so it always stays a real file.

## Stow gotchas (learned the hard way)

- **Installing packages before stowing, on a fresh machine.** `bootstrap-host.sh`/
  `post-create.sh` install packages (apt/flatpak/Ghostty/Homebrew/dnf) *before*
  stowing. Several of those create their own default config file at the same
  path stow wants to symlink (Ghostty's config dir, possibly others) - plain
  `stow` then refuses every one of those as a conflict and aborts entirely,
  which is exactly what happened on `dell`. Fix (already applied in both
  scripts): `stow --no-folding --adopt -t ~ .` followed immediately by
  `git checkout -- .`.
  `--adopt` claims the real file instead of erroring, but it does so by
  **overwriting the repo's tracked content with whatever the installer's
  default file contained** - the `git checkout` right after discards that and
  restores the curated dotfiles version. Net effect: every target ends up a
  symlink, with our content, not the installer's defaults. Worth running
  `git status` between the two commands once, just to see what actually got
  adopted/overwritten before discarding it.
- **Folding defeats nested `.stow-local-ignore` rules.** If stow can fold a
  whole directory into one symlink, it does so without consulting ignore
  rules for children - so a nested exclusion (e.g. `service.json` inside
  `.config/opencode`) silently did nothing until `--no-folding` was added.
  Both scripts use `--no-folding` now; it costs more individual symlinks but
  makes per-path exclusions reliable.
- **A `.stow-local-ignore` replaces stow's built-in ignore list.** `.git`,
  `.gitignore` and the ignore file itself have to be re-listed explicitly or
  `~/.git` becomes a symlink into the repo.
- **Apps rewriting config files in place, after initial setup.** On `dell`,
  `.config/ghostty` and `.local/share/mc` both started as stow symlinks and
  silently ended up as real files later - some app rewrote its config file
  directly instead of following the symlink through to the git-tracked
  target, breaking the link. Same root cause and same fix as above, just
  needed periodically rather than once: `cd ~/dotfiles && stow --adopt -t ~ .
  && git checkout -- .`, or just watch for it via `find ~/dotfiles -type f`
  (should never show a file that's supposed to be a symlink turning real).
- **Absolute vs. relative symlinks.** `stow` refuses to manage (and aborts
  the *entire* operation for) any existing symlink it didn't create itself -
  including ones that already point to the right place, if they're absolute
  paths instead of the relative paths `stow` generates (e.g. a manually
  created `~/.config/nvim/init.lua -> /home/sago/dotfiles/...` instead of
  `-> ../../dotfiles/...`). Fix: delete the offending symlink(s) and let
  `stow` recreate them - it'll then "own" them correctly.
- **Never re-stow while using a tool that reads its own live config.** Found
  out the hard way mid-migration-prep: this dotfiles work was done *inside
  opencode itself*, which reads `~/.config/opencode/opencode.json` live.
  Deleting that file to prepare for stow broke the running session
  immediately. If a tool's own config is being stowed, do that step from a
  *different* shell/tool than the one being reconfigured, or expect to
  need a manual restore mid-way.



- **Host maintenance console**: the distro's stock terminal app. Zero
  setup, used rarely (podman/distrobox issues, host package upgrades). It
  already gets full zsh/tmux/neovim QOL since the host runs the same
  dotfiles + its own `Brewfile.host` install.
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
- The `.zshrc` auto-attach (`exec tmux new-session -A -s main`) uses a
  **named socket inside the container** (`tmux -L dev`, gated on
  `/run/.containerenv`). Without this, host and container would share one
  "main" session instead of two independent ones: distrobox shares the
  host's PID/net namespaces by default *and* bind-mounts `/tmp` for GUI/
  D-Bus integration, so the default tmux socket
  (`/tmp/tmux-$UID/default`) is literally the same server on both sides -
  not isolated the way separate containers normally are. (An earlier draft
  of this doc assumed namespace separation would keep the sessions apart;
  it doesn't, hence the explicit `-L dev`.)

## Google Drive secondary sync

A second, ongoing safety net on top of the one-time migration tarball below
- `Documents`/`Pictures`/`Downloads`/etc plus `Projects`/`medusa`/
`efs-utils`/`scripts`/`bin` get kept in sync with the root of the `gdrive`
remote, host-only (not run inside the container).

Why `rclone` instead of a GUI client: Google doesn't ship a native Linux
Drive app. The only real GUI option (Insync) is paid; `rclone` is free,
scriptable, and fits the rest of this repo's "explicit and curated, not a
black box" approach.

- **Allowlist, not denylist.** `backup/gdrive-filter.txt` lists exactly
  which top-level dirs get synced - same approach as the one-time backup
  tarball below, for the same reason: app-state/config dotdirs
  (`.config`, `.local`, `.cache`, `.ssh`, `.aws`, ...) multiply over time as
  new tools get installed, so a denylist needs constant upkeep to stay
  complete. An allowlist just... doesn't include them, ever, with zero
  maintenance.
- **`Projects` is deliberately excluded**, per a security team request -
  it's left out of the allowlist entirely rather than added as an explicit
  exclude rule.
- **`rclone bisync`, not `sync`** - true two-way sync. A change made in
  the Drive web UI (edit, add, delete) propagates down to the local
  machine on the next run, same as a local change propagates up. This
  replaced an earlier one-way `rclone sync` design that mirrored into a
  `Backup` subfolder on Drive (local → Drive only); switched to bisync so
  that sorting/organizing files from the Drive web UI (see the Documents
  merge below) flows back down automatically instead of requiring a
  separate pull step.
  - **Filters file, not `--filter-from`**: bisync specifically wants
    `--filters-file` - it stores a hash of that file and refuses to run
    (demanding a fresh `--resync`) if the file changes between runs. Any
    edit to `gdrive-filter.txt` needs a manual one-off
    `rclone bisync "$HOME" gdrive: --filters-file gdrive-filter.txt --resync`
    before the timer's normal (no `--resync`) runs will work again.
  - **Conflict handling**: if the same file changes on both sides between
    runs, the default (`--conflict-resolve none`) keeps both, renaming the
    loser with a `.conflict1`/`.conflict2` suffix rather than picking a
    winner automatically - sort those by hand when they show up.
  - **Safety check**: bisync refuses to propagate deletions past
    `--max-delete` (default 50% of files) and aborts instead - a stuck/
    failed run shows up as an `ERROR`/non-zero exit in the journal, not a
    silent success like plain `sync` was. Check periodically, not just
    assumed-fine.
  - **State lives in `~/.cache/rclone/bisync/`** (per-path-pair listing
    snapshots). Treat it as precious - deleting it forces a `--resync`
    (safe, just re-baselines; not destructive, but needs a manual run).
- **Documents merge from the old Windows migration (one-time, 2026-11-05)**:
  Drive already had a top-level `Documents` folder from the original
  Windows → Linux migration tarball, containing a full nested dump
  (`Documents/Pictures`, `Documents/Desktop`, loose misc files, etc.) -
  not a clean match for a `Documents` folder synced 1:1 with
  `~/Documents`. Resolved by renaming it to `Documents_win_legacy` *before*
  the first `--resync` - an allowlist entry only matches its exact literal
  path, so the differently-named folder falls through to the trailing
  `- *` deny-all automatically and is simply never touched by bisync, no
  exclude rule needed. The one-off `--resync` then populated fresh
  `Documents`/`Pictures`/etc. at Drive root purely from local content.
  `Documents_win_legacy` is being sorted manually via the Drive web UI
  into the proper root folders at leisure - bisync picks up anything moved
  into an allowlisted folder and copies it down to `$HOME` on the next
  run (new files are only ever copied, never deleted, so this is safe to
  do gradually with the timer running). Watch for Drive's lack of
  same-name collision prompts when dragging files over (rename manually on
  conflict rather than leaving duplicate names in one folder - rclone
  tends to warn/skip on those). The old `Backup/` folder from the
  pre-bisync one-way design was merged into the respective root folders
  and can be purged (`rclone purge gdrive:Backup`) once confirmed clean.
- **Not stowed.** `backup/gdrive-backup.sh` and `gdrive-filter.txt` are
  referenced by their repo path directly (`~/dotfiles/backup/...`), same
  pattern as `Brewfile`/`distrobox/*` - no need for them to live at a
  specific `$HOME` path. The systemd units *do* need to be stowed (systemd
  only looks in `~/.config/systemd/user/`), so those live under `.config/`
  as usual.
- **Every 30 minutes**, via `gdrive-backup.timer` (systemd user timer) - not
  continuous/real-time. A fixed-interval full-tree scan+compare every
  minute would be wasteful (CPU/disk, and repeated Drive API listing calls
  risk quota throttling as Projects/media grow) for what's a secondary
  safety-net sync, not live collaboration. 30 min means "lose at most
  that much" if the disk dies - a fine bar for this.
- **Lingering is enabled** (`loginctl enable-linger`, done once by
  `bootstrap-host.sh`) so the timer keeps firing even when logged out -
  without it, systemd stops the whole `--user` instance (and this timer
  with it) on logout, e.g. a fast user-switch or closing a non-sleeping
  session. Check with `loginctl show-user "$USER" --property=Linger`.
- **One-time setup, not scripted**: `rclone config` needs an interactive
  browser for Google's OAuth flow, so it can't be automated blind. Create
  a remote named exactly `gdrive` (type: Google Drive). `rclone.conf` (the
  resulting token) lives at `~/.config/rclone/rclone.conf` - **never**
  committed (gitignored defensively even though nothing in this repo stows
  into that path, so there's no real exposure risk today).
  `bootstrap-host.sh` checks for the `gdrive:` remote and enables the timer
  automatically if found, otherwise prints the one-time setup steps.
- **Logging goes to the user journal, not a file.** The service is a
  `Type=oneshot` with no `--log-file` passed to rclone, so its stdout/stderr
  land in the systemd user journal, which journald already size-caps and
  rotates - no log file growing forever, nothing to rotate by hand. Check
  recent runs with `journalctl --user -u gdrive-backup --since -1d`.

## Step-by-step

### 1. On the old WSL box

1. Finish reviewing/pushing the dotfiles repo (this commit).
2. Make sure every project directory is actually pushed - these were
   found to be loose collections of repos, not single ones; check each
   subfolder individually before wiping anything:
   `Projects/` (contains many independent repos, e.g. `artifacts_*`, `opscli`),
   `medusa/`.
   (`devops-book-pp-code/`, `ODIN/`, `workfx-zbi4-backup/` were old learning
   exercises - already deleted, not carried forward.)
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
       -czf ~/home-backup.tar.gz -C ~ Projects medusa efs-utils scripts bin
   ```
   Deliberately not included: `go/` (contents are just `~/go/pkg/mod`, Go's
   module download cache - 963MB, fully reinstallable via `go mod download`,
   not worth backing up) and `tmp/` (scratch space - a leftover test tmux
   plugin clone and a non-sensitive OIDC URL, nothing of value found).
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
host-only Homebrew install at `/home/linuxbrew/.linuxbrew`, runs
`brew bundle --file=Brewfile.host`, stows the dotfiles, installs oh-my-zsh
and the tmux plugins, then assembles the `dev` Fedora container from
`distrobox.ini`.

### 3. Enter the container and finish setup

```
distrobox enter dev
bash ~/dotfiles/distrobox/post-create.sh
```

Stows the dotfiles again inside the container (same repo, same symlinks),
installs the container's own Homebrew at `/home/linuxbrew/.linuxbrew`,
runs the full `Brewfile`, and installs krew plugins plus the headless
Neovim/Mason bootstrap.

### 4. Restore secrets and data

```
gpg -d ~/secrets.tar.gz.gpg | tar xzf - -C ~
chmod 600 ~/.ssh/id_* ~/.ssh/pp_rdc* ~/.ssh/sg-rdc* ~/.ssh/ray-autoscaler_ssh_key
tar xzf ~/home-backup.tar.gz -C ~
```

### 5. Fix environment-specific config that can't just be copied

These broke on the move from WSL and need to be redone rather than restored:

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
- Set zsh as the default shell. On the host, the brew zsh must be
  registered as a login shell first (`chsh` refuses anything not listed in
  `/etc/shells`) - `bootstrap-host.sh` does this automatically, but `chsh`
  itself needs your password interactively:
  `chsh -s /home/linuxbrew/.linuxbrew/bin/zsh`
  Inside the container, `post-create.sh` registers and sets the shell
  automatically (container has its own `/etc/passwd`/`/etc/shells`,
  separate from the host, and distrobox's created user typically has
  passwordless sudo).
- Point Ghostty's `command` config at `~/.local/bin/dev-shell` (already in
  the stowed `~/.config/ghostty/config`).

### 6. Rebuilding/upgrading the container later

```
distrobox stop dev && distrobox rm dev
cd ~/dotfiles/distrobox && ./bootstrap-host.sh   # bumps the Fedora image too if you edit distrobox.ini
distrobox enter dev && bash ~/dotfiles/distrobox/post-create.sh
```

$HOME (and everything in it - dotfiles, keys, projects) is untouched by
this, since all of that lives on the host side of the shared home mount.
The container's own Homebrew install *is* lost, and `post-create.sh`
reinstalls it - expect the rebuild to take as long as the first run.

## Explicitly excluded from backup (regenerate/reinstall instead of copying)

- `.cache/`, `.npm`, `.bun`, `snap/`
- `.*_history`, `.zcompdump*` (several stale ones from old hostnames)
- `*.bak`, `*.old`, `known_hosts.bak`, `known_hosts.old`
- `.kube/cache`, `.aws/sso/cache`, `.aws/cli/cache`
- `.vscode-server`, `.vscode-remote-containers` (WSL Remote-* artifacts, N/A natively)
- `~/.local/share/nvim`, `~/.local/state/nvim` - Mason's compiled LSP/linter/
  DAP binaries live here, OS/arch-specific and never portable (see Neovim &
  tmux reproducibility above). `post-create.sh` rebuilds this from scratch.
- `.viminfo` - cache/history, now gitignored too (see above)
- build artifacts, e.g. `efs-utils/src/proxy/target`
