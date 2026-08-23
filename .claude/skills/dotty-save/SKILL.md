---
name: dotty-save
description: Capture current packages, shell config, aliases, and terminal prefs into the user's private dotty repo (~/.dotty) and push. Use when the user wants to save/sync/snapshot their dotfiles, packages, aliases, or preferences - e.g. "/dotty-save", "save my new aliases", "sync my dotfiles". Optional args describe a specific thing to add (a new alias, package, or setting).
---

# dotty-save

Sync the live machine state into `~/.dotty` (the user's private dotty repo) and push. This is the curated version of the `dotpush` shell alias (`~/.dotty/save.sh`): same end result, but you review the diff, place things in the right file, and catch junk before it's committed.

The live rc files (`~/.zshrc`, `~/.zprofile`, `~/.bashrc`, `~/.bash_profile`, `~/.config/ghostty/config`) are symlinks into the repo, so config edits are captured automatically by git - the work here is pulling first, re-dumping package lists, folding in anything the user named, and pushing a clean commit. Git config (`~/.gitconfig`) is deliberately NOT managed by dotty.

1. **Pull first** so the commit lands cleanly:
   ```sh
   git -C ~/.dotty pull --ff-only
   ```

2. **Check the symlinks are intact** - if a live rc file is a real file instead of a symlink into `~/.dotty`, something clobbered it; diff it against the repo version, fold real changes into the repo, and re-run `~/.dotty/install.sh --no-packages`.

3. **Fold in anything the user named**, putting it where it belongs:
   - aliases and portable env vars / PATH → `~/.dotty/shell/common.sh` (POSIX sh - sourced by both zsh and bash)
   - zsh-only behavior → `~/.dotty/zsh/zshrc` (or `zprofile` for login-shell setup); bash-only → `~/.dotty/bash/bashrc`
   - terminal prefs → `~/.dotty/ghostty/config`
   - fork-level settings (preferred shell, gist id) → `~/.dotty/dotty.conf`
   - Anything machine-specific (work-only paths, per-box secrets) belongs in untracked `~/.zshrc.local` / `~/.bashrc.local`, not the repo - say so instead of committing it.

4. **Re-dump packages:**
   - macOS: `brew bundle dump --file=~/.dotty/Brewfile --force`, then review `git -C ~/.dotty diff Brewfile`. Keep genuine additions; if something transient or experimental appears (a one-off tool the user was just trying), ask before keeping it only if unsure - default to keeping.
   - Debian/Ubuntu: `save.sh` (step 6) auto-captures human-installed packages from apt history into `packages/apt.txt`; review its additions in the diff and prune anything machine-specific the user wouldn't want on every box.

5. **Review the full diff** (`git -C ~/.dotty status` and `git -C ~/.dotty diff`). Never commit secrets: scan the diff for tokens, keys, or passwords and pull them out into `~/.zshrc.local` instead if found.

6. **Commit and push** via the repo's own script (it commits, rebases on the remote, pushes, and re-mirrors the public bootstrap gist if `bootstrap.sh` changed):
   ```sh
   ~/.dotty/save.sh "<one-line summary of what changed>"
   ```

7. **Report**: one short summary of what was captured (new packages, changed configs, anything skipped) - or "no changes to save" if the tree was clean and the dump produced no diff.
