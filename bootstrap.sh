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

# --- ui: inline copy of lib/ui.sh (this script must run standalone via
# curl|sh, before the repo exists) - keep the two in sync ---
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]*8*) DOT='●' DOT_OPEN='○' DOTS='●●●' SEP=' ·' ;;
  *)                DOT='*' DOT_OPEN='o' DOTS='==>' SEP=':' ;;
esac
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK='\033[1;32m' C_INFO='\033[1;34m' C_WARN='\033[1;33m' C_DIM='\033[2m' C_OFF='\033[0m'
else
  C_OK='' C_INFO='' C_WARN='' C_DIM='' C_OFF=''
fi
info() { printf "${C_INFO}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*"; }
ok()   { printf "${C_OK}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*"; }
warn() { printf "${C_WARN}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*" >&2; }
item()      { printf "  ${C_OK}%s${C_OFF} %-9s %s\n" "$DOT" "$1" "$2"; }
item_open() { printf "  ${C_DIM}%s${C_OFF} %-9s %s\n" "$DOT_OPEN" "$1" "$2"; }

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
  info "migrated ~/.dotfiles to ~/.dotty"
fi

if [ ! -d "$DOTTY/.git" ]; then
  # Fresh Macs: the 1Password SSH agent may be running but not exported yet.
  OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  if ! ssh_ok && [ -S "$OP_SOCK" ]; then
    export SSH_AUTH_SOCK="$OP_SOCK"
  fi
  info "fetching your dots"
  if ssh_ok; then
    git clone "$REPO_SSH" "$DOTTY"
  else
    info "no SSH key for GitHub; cloning over https (prompts for credentials)"
    git clone "$REPO_HTTPS" "$DOTTY"
  fi
else
  OLD="$(git -C "$DOTTY" rev-parse HEAD)"
  # rebase keeps any local not-yet-pushed dots and survives upstream history
  # rewrites (patch-identical commits are skipped)
  git -C "$DOTTY" pull --rebase --autostash --quiet || {
    git -C "$DOTTY" rebase --abort >/dev/null 2>&1 || true
    warn "couldn't reconcile with the remote automatically."
    echo "   If this machine has no local changes worth keeping, run:" >&2
    echo "     git -C ~/.dotty fetch && git -C ~/.dotty reset --hard origin/main && dotpull" >&2
    exit 1
  }
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
  ok "fresh dots installed - welcome"
  # curl|sh can't refresh the calling shell, so hand this terminal a new one
  # directly (stdin is the curl pipe - rewire it to the terminal).
  if command -v "$PREFERRED_SHELL" >/dev/null 2>&1 && [ -t 1 ] && [ -e /dev/tty ]; then
    exec "$PREFERRED_SHELL" -il </dev/tty
  fi
  info "open a new shell to pick up dotpull/dotpush"
  exit 0
fi
NEW="$(git -C "$DOTTY" rev-parse HEAD)"
if [ "$OLD" = "$NEW" ]; then
  ok "everything's tidy - all dots in a row"
  exit 0
fi
added() { git -C "$DOTTY" diff "$OLD" "$NEW" -- "$@" | grep '^+[^+]' | cut -c2-; }
PKGS="$( { added packages/apt.txt | grep -v '^[[:space:]]*$' || true
           added Brewfile | sed -n 's/^\(brew\|cask\|mas\|vscode\) *"\{0,1\}\([^",]*\).*/\2/p'; } | xargs )"
ALIASES="$(added shell/common.sh | sed -n 's/.*alias \([A-Za-z0-9_-]*\)=.*/\1/p' | xargs)"
OTHER="$(git -C "$DOTTY" diff --name-only "$OLD" "$NEW" \
  | grep -v -e '^packages/apt.txt$' -e '^Brewfile$' -e '^shell/common.sh$' | xargs)"
COUNT="$(git -C "$DOTTY" rev-list --count "$OLD..$NEW")"
if [ "$COUNT" = 1 ]; then ok "1 new dot landed:"; else ok "$COUNT new dots landed:"; fi
[ -n "$PKGS" ]    && item packages "$PKGS"
[ -n "$ALIASES" ] && item aliases "$ALIASES"
[ -n "$OTHER" ]   && item_open changed "$OTHER"
exit 0
