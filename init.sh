#!/usr/bin/env sh
# dotty init - first-run setup for a fresh copy of dotty with no payload yet.
# Builds your preference set (the "payload": rc files, aliases, packages),
# commits it, and hands off to install.sh. Runs automatically from
# bootstrap.sh/install.sh when the payload is missing; safe to run directly.
set -eu

DOTTY="$(cd "$(dirname "$0")" && pwd)"
. "$DOTTY/lib/ui.sh"
. "$DOTTY/lib/capture.sh"

if [ -f "$DOTTY/shell/common.sh" ]; then
  info "already initialized (payload exists); nothing to do"
  exit 0
fi

if [ ! -e /dev/tty ] || ! [ -t 1 ]; then
  warn "first run needs a choice from you - run ~/.dotty/init.sh in a terminal"
  exit 1
fi

info "no preferences here yet. How should we start?"
echo "    [c] capture this machine's current dotfiles and packages (default)"
echo "    [e] start from the example set (a sane, generic baseline)"
echo "    [b] start blank"
printf "${C_INFO}%s${C_OFF} dotty${C_DIM}%s${C_OFF} your call [c/e/b]: " "$DOTS" "$SEP"
read -r CHOICE </dev/tty || CHOICE=c
case "$CHOICE" in
  [eE]*) CHOICE=example ;;
  [bB]*) CHOICE=blank ;;
  *)     CHOICE=capture ;;
esac
info "starting with: $CHOICE"

mkdir -p "$DOTTY/shell" "$DOTTY/zsh" "$DOTTY/bash" "$DOTTY/ghostty" "$DOTTY/packages"

# Minimal payload stubs; capture/example overwrite or extend them below.
write_stubs() {
  cat > "$DOTTY/shell/common.sh" <<'EOF'
# Shared environment + aliases - POSIX sh, sourced by BOTH zshrc and bashrc.
# Anything here must work in every supported shell; shell-specific config
# belongs in zsh/zshrc or bash/bashrc.

# dotty - dotpull pulls latest + reinstalls; dotpush pushes this machine's changes
alias dotpull='~/.dotty/bootstrap.sh && exec "$SHELL"'
alias dotpush="~/.dotty/save.sh"
EOF
  cat > "$DOTTY/zsh/zshrc" <<'EOF'
# ~/.zshrc - managed by dotty (symlinked; edit in ~/.dotty and dotpush)

# --- shared env + aliases (portable across shells) ---
[ -f "$HOME/.dotty/shell/common.sh" ] && source "$HOME/.dotty/shell/common.sh"

# --- machine-local overrides, not tracked in git ---
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF
  cat > "$DOTTY/zsh/zprofile" <<'EOF'
# ~/.zprofile - managed by dotty
EOF
  cat > "$DOTTY/bash/bashrc" <<'EOF'
# ~/.bashrc - managed by dotty (symlinked; edit in ~/.dotty and dotpush)

case $- in *i*) ;; *) return ;; esac

# --- shared env + aliases (portable across shells) ---
[ -f "$HOME/.dotty/shell/common.sh" ] && . "$HOME/.dotty/shell/common.sh"

# --- machine-local overrides, not tracked in git ---
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
EOF
  cat > "$DOTTY/bash/bash_profile" <<'EOF'
# ~/.bash_profile - managed by dotty. Login shells: same as interactive.
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF
  touch "$DOTTY/packages/apt.txt"
  cat > "$DOTTY/packages/apt-ignore.txt" <<'EOF'
# Packages dotpush must never auto-capture into apt.txt.
# Prune a package from apt.txt? Move its line here or it will come back.
EOF
  printf '' > "$DOTTY/Brewfile"
}

# Import an existing rc file as the payload version, keeping dotty's hooks.
import_rc() {
  src="$1" dst="$2" localfile="$3"
  [ -f "$src" ] && [ ! -L "$src" ] || return 0
  info "importing $src"
  cp "$src" "$DOTTY/$dst"
  if ! grep -q '\.dotty/shell/common\.sh' "$DOTTY/$dst"; then
    cat >> "$DOTTY/$dst" <<EOF

# --- dotty: shared env + aliases (portable across shells) ---
[ -f "\$HOME/.dotty/shell/common.sh" ] && . "\$HOME/.dotty/shell/common.sh"

# --- machine-local overrides, not tracked in git ---
[ -f "\$HOME/$localfile" ] && . "\$HOME/$localfile"
EOF
  fi
}

case "$CHOICE" in
  capture)
    write_stubs
    import_rc "$HOME/.zshrc"        zsh/zshrc         .zshrc.local
    import_rc "$HOME/.zprofile"     zsh/zprofile      .zprofile.local
    import_rc "$HOME/.bashrc"       bash/bashrc       .bashrc.local
    import_rc "$HOME/.bash_profile" bash/bash_profile .bash_profile.local
    if [ -f "$HOME/.config/ghostty/config" ] && [ ! -L "$HOME/.config/ghostty/config" ]; then
      info "importing ghostty config"
      cp "$HOME/.config/ghostty/config" "$DOTTY/ghostty/config"
    fi
    capture_brewfile
    capture_apt_packages
    ;;
  example)
    cp -R "$DOTTY/example/shell"    "$DOTTY/"
    cp -R "$DOTTY/example/zsh"      "$DOTTY/"
    cp -R "$DOTTY/example/bash"     "$DOTTY/"
    cp -R "$DOTTY/example/ghostty"  "$DOTTY/"
    cp -R "$DOTTY/example/packages" "$DOTTY/"
    cp "$DOTTY/example/Brewfile"    "$DOTTY/Brewfile"
    ;;
  blank)
    write_stubs
    ;;
esac

# ghostty config must exist for install.sh's symlink
[ -f "$DOTTY/ghostty/config" ] || printf '# ghostty config - managed by dotty\n' > "$DOTTY/ghostty/config"

# dotty.conf: derive sensible defaults for this user
if [ "$CHOICE" = "example" ] && [ -f "$DOTTY/example/dotty.conf" ]; then
  cp "$DOTTY/example/dotty.conf" "$DOTTY/dotty.conf"
else
  case "${SHELL:-}" in */zsh) PS=zsh ;; */bash) PS=bash ;; *) PS=zsh ;; esac
  [ -d "$HOME/.oh-my-zsh" ] && OMZ=yes || OMZ=no
  cat > "$DOTTY/dotty.conf" <<EOF
# dotty.conf - fork-me settings, read by install.sh / bootstrap.sh / save.sh.
# POSIX sh syntax (this file is sourced).

# Which shell dotty sets up as the default and hands you after install: zsh or bash.
PREFERRED_SHELL=$PS

# Install oh-my-zsh? yes or no. Independent of PREFERRED_SHELL.
WANT_OH_MY_ZSH=$OMZ

# Public gist mirroring bootstrap.sh (lets the one-liner run before your
# private repo is cloned). Create yours with: gh gist create --public bootstrap.sh
# Leave empty to skip mirroring.
BOOTSTRAP_GIST_ID=
EOF
fi

if git -C "$DOTTY" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DOTTY" add -A
  git -C "$DOTTY" commit -q -m "dotty init: $CHOICE on $(hostname -s)" 2>/dev/null \
    || git -C "$DOTTY" -c user.name="$(id -un)" -c user.email="$(id -un)@$(hostname -s)" \
         commit -q -m "dotty init: $CHOICE on $(hostname -s)"
  ok "committed your starting dots ($CHOICE)"
  case "$(git -C "$DOTTY" remote get-url origin 2>/dev/null)" in
    *hous/dotty*)
      info "this clone still points at the dotty template, which you can't push to."
      echo "    Make it yours:  gh repo create dotty --private --source $DOTTY --push"
      echo "    (or create a private repo and: git -C ~/.dotty remote set-url origin <your-url>)"
      ;;
  esac
fi

"$DOTTY/install.sh" "$@"
