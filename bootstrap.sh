#!/usr/bin/env sh
# dotty bootstrap - get your dots in a row on any machine, idempotently.
# Mirrored as a public gist so it can run before the (private) repo exists:
#
#   curl -fsSL https://gist.githubusercontent.com/hous/ff496d87cc150d8d51262673e5278ecf/raw/bootstrap.sh | sh
#
# Clones the repo if this machine doesn't have it, updates it if it does,
# then runs install.sh (packages, symlinks, prefs). Extra args (e.g.
# --no-packages) are passed through to install.sh.
set -eu

DOTTY="$HOME/.dotty"
# Point these two lines at YOUR dots repo before using the curl one-liner.
REPO_SSH="git@github.com:YOURNAME/dotty.git"
REPO_HTTPS="https://github.com/YOURNAME/dotty.git"

ssh_ok() {
  # </dev/null so ssh can't swallow keystrokes buffered in the terminal
  ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com </dev/null 2>&1 \
    | grep -q "successfully authenticated"
}

# Migrate installs from before the great renaming (~/.dotfiles -> ~/.dotty).
if [ ! -e "$DOTTY" ] && [ -e "$HOME/.dotfiles/.git" ]; then
  if [ -L "$HOME/.dotfiles" ]; then
    ln -s "$(readlink "$HOME/.dotfiles")" "$DOTTY"
  else
    mv "$HOME/.dotfiles" "$DOTTY"
    ln -sfn "$DOTTY" "$HOME/.dotfiles"
  fi
  echo "==> dotty: migrated ~/.dotfiles to ~/.dotty"
fi

if [ ! -d "$DOTTY/.git" ]; then
  # Fresh Macs: the 1Password SSH agent may be running but not exported yet.
  OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  if ! ssh_ok && [ -S "$OP_SOCK" ]; then
    export SSH_AUTH_SOCK="$OP_SOCK"
  fi
  echo "==> dotty: fetching your dots"
  if ssh_ok; then
    git clone "$REPO_SSH" "$DOTTY"
  else
    echo "==> dotty: no SSH key for GitHub; cloning over https (prompts for credentials)"
    git clone "$REPO_HTTPS" "$DOTTY"
  fi
else
  OLD="$(git -C "$DOTTY" rev-parse HEAD)"
  git -C "$DOTTY" pull --ff-only --quiet
fi

if [ ! -f "$DOTTY/shell/common.sh" ]; then
  # No payload yet: first run on a fresh copy of dotty. init.sh builds your
  # preference set (capture/example/blank) and runs install.sh itself.
  "$DOTTY/init.sh" "$@"
else
  "$DOTTY/install.sh" "$@"
fi

PREFERRED_SHELL=zsh
[ -f "$DOTTY/dotty.conf" ] && . "$DOTTY/dotty.conf"

# Report what this pull actually brought to the machine.
if [ -z "${OLD:-}" ]; then
  echo "==> dotty: fresh dots installed - welcome"
  # curl|sh can't refresh the calling shell, so hand this terminal a new one
  # directly (stdin is the curl pipe - rewire it to the terminal).
  if command -v "$PREFERRED_SHELL" >/dev/null 2>&1 && [ -t 1 ] && [ -e /dev/tty ]; then
    exec "$PREFERRED_SHELL" -il </dev/tty
  fi
  echo "==> dotty: open a new shell to pick up dotpull/dotpush"
  exit 0
fi
NEW="$(git -C "$DOTTY" rev-parse HEAD)"
if [ "$OLD" = "$NEW" ]; then
  echo "==> dotty: everything's tidy - nothing new"
  exit 0
fi
added() { git -C "$DOTTY" diff "$OLD" "$NEW" -- "$@" | grep '^+[^+]' | cut -c2-; }
PKGS="$( { added packages/apt.txt | grep -v '^[[:space:]]*$' || true
           added Brewfile | sed -n 's/^\(brew\|cask\|mas\|vscode\) *"\{0,1\}\([^",]*\).*/\2/p'; } | xargs )"
ALIASES="$(added shell/common.sh | sed -n 's/.*alias \([A-Za-z0-9_-]*\)=.*/\1/p' | xargs)"
OTHER="$(git -C "$DOTTY" diff --name-only "$OLD" "$NEW" \
  | grep -v -e '^packages/apt.txt$' -e '^Brewfile$' -e '^shell/common.sh$' | xargs)"
echo "==> dotty: new dots landed ($(git -C "$DOTTY" rev-list --count "$OLD..$NEW") commit(s)):"
[ -n "$PKGS" ]    && echo "    new packages: $PKGS"
[ -n "$ALIASES" ] && echo "    new aliases:  $ALIASES"
[ -n "$OTHER" ]   && echo "    changed:      $OTHER"
exit 0
