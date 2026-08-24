#!/usr/bin/env sh
# dotty save - push this machine's new packages/configs/aliases to the repo.
# Aliased as `dotpush`. Optional args become the commit message:
#
#   dotpush                          # auto message: "Sync from <host> on <date>"
#   dotpush add eza alias            # commit message: "add eza alias"
#
# Configs are symlinked into the repo, so edits are already here - this script
# re-dumps packages, commits everything, syncs with the remote, and pushes.
set -eu

DOTTY="$HOME/.dotty"
BOOTSTRAP_GIST_ID=""
[ -f "$DOTTY/dotty.conf" ] && . "$DOTTY/dotty.conf"
cd "$DOTTY"
. "$DOTTY/lib/ui.sh"

# Fold in rc files that lost their symlink (some editors replace a symlink with
# a real file on save), so edits to them are never silently missed.
heal() {
  dst="$1" rel="$2"
  { [ -e "$dst" ] && [ ! -L "$dst" ]; } || return 0
  info "$dst is a real file (symlink was clobbered); folding it back in"
  cp "$dst" "$DOTTY/$rel"
  ln -sfn "$DOTTY/$rel" "$dst"
}
heal "$HOME/.zshrc"                 zsh/zshrc
heal "$HOME/.zprofile"              zsh/zprofile
heal "$HOME/.bashrc"                bash/bashrc
heal "$HOME/.bash_profile"          bash/bash_profile
heal "$HOME/.config/ghostty/config" ghostty/config

# capture packages: Brewfile on macOS, human-installed apt packages on Debian/Ubuntu
. "$DOTTY/lib/capture.sh"
capture_brewfile
capture_apt_packages

if [ -n "$(git status --porcelain)" ]; then
  # crude secret check before anything is committed
  if git diff HEAD | grep -nE 'gh[opsu]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]+PRIVATE KEY'; then
    warn "that looks like a secret - move it to ~/.zshrc.local or ~/.bashrc.local, then re-run"
    exit 1
  fi
  git add -A
  git commit -m "${*:-Sync from $(hostname -s) on $(date '+%Y-%m-%d %H:%M')}"
else
  info "no new dots on this machine"
fi

info "syncing with remote"
git pull --rebase --autostash

if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]; then
  CHANGED="$(git diff --name-only '@{u}' HEAD)"
  git push
  ok "dots pushed"
  case "$CHANGED" in
    *bootstrap.sh*)
      if [ -n "$BOOTSTRAP_GIST_ID" ]; then
        info "bootstrap.sh changed; re-mirroring public gist"
        gh gist edit "$BOOTSTRAP_GIST_ID" --add "$DOTTY/bootstrap.sh" 2>/dev/null \
          || warn "gist mirror failed - run as the gist-owning gh account: gh gist edit $BOOTSTRAP_GIST_ID --add ~/.dotty/bootstrap.sh"
      fi
      ;;
  esac
else
  ok "nothing to push - the remote has all your dots"
fi
