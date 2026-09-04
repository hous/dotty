#!/usr/bin/env bash
# dotty installer - idempotent, safe to re-run any time.
# Usage: ~/.dotty/install.sh [--no-packages]
set -euo pipefail

DOTTY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

# No payload yet? Hand over to init, which builds it and re-runs this script.
if [ ! -f "$DOTTY/shell/common.sh" ]; then
  exec "$DOTTY/init.sh" "$@"
fi

# fork-me settings (see dotty.conf)
PREFERRED_SHELL=zsh
WANT_OH_MY_ZSH=no
[ -f "$DOTTY/dotty.conf" ] && . "$DOTTY/dotty.conf"

INSTALL_PACKAGES=1
[ "${1:-}" = "--no-packages" ] && INSTALL_PACKAGES=0

. "$DOTTY/lib/ui.sh"
have() { command -v "$1" >/dev/null 2>&1; }

# Symlink $1 (repo-relative) to $2 (absolute), backing up any real file in the way.
# Silent no-op when the link is already correct.
link() {
  local src="$DOTTY/$1" dst="$2" bak
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && return 0
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    bak="$dst.bak"
    [ -e "$bak" ] && bak="$bak.$(date +%Y%m%d%H%M%S)"
    info "backing up $dst -> $bak"
    mv "$dst" "$bak"
    # Don't strand machine-specific config (venvs, tokens, paths) in the backup:
    # seed the .local file dotty's rc sources last, pointing at it.
    case "$dst" in
      "$HOME/.zshrc"|"$HOME/.bashrc")
        if [ ! -e "$dst.local" ]; then
          printf '# machine-local overrides, sourced last by dotty. Your previous %s\n# was saved at %s - move anything machine-specific here.\n' "$dst" "$bak" > "$dst.local"
          info "seeded $dst.local - review $bak for machine-specific bits to move there"
        fi
        ;;
    esac
  fi
  ln -sfn "$src" "$dst"
  info "linked $dst -> $src"
}

# Put brew on PATH from either prefix (Apple Silicon or Intel). Returns 1 if not installed.
brew_env() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
  done
  return 1
}

# --- packages ---
if [ "$INSTALL_PACKAGES" = 1 ]; then
  if [ "$OS" = "Darwin" ]; then
    if ! have brew && ! brew_env; then
      info "installing Homebrew"
      NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      brew_env
    fi
    info "installing Brewfile packages"
    brew bundle --file="$DOTTY/Brewfile" || warn "brew bundle finished with some failures (ok to re-run)"
  elif have apt-get; then
    # Only ask apt for packages that aren't installed yet: feeding it the whole
    # list every pull is slow, needs sudo, and upgrades things behind your back.
    MISSING="$(while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed' || printf '%s\n' "$pkg"
      done < "$DOTTY/packages/apt.txt")"
    if [ -n "$MISSING" ]; then
      info "installing apt packages:$(printf ' %s' $MISSING)"
      sudo apt-get update -qq
      if ! printf '%s\n' "$MISSING" | xargs sudo apt-get install -y -qq; then
        info "batch install failed; retrying one by one"
        while IFS= read -r pkg; do
          [ -n "$pkg" ] || continue
          sudo apt-get install -y -qq "$pkg" || warn "skipped $pkg (not available here)"
        done <<<"$MISSING"
      fi
    else
      info "apt packages all present"
    fi
    if ! have gh; then
      info "installing GitHub CLI"
      sudo mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update -qq && sudo apt-get install -y -qq gh
    fi
  else
    warn "no supported package manager found; skipping packages (install zsh, git, curl manually)"
  fi

  # standalone tools no package manager tracks (see packages/tools.sh)
  if [ -f "$DOTTY/packages/tools.sh" ]; then
    . "$DOTTY/packages/tools.sh"
  fi
fi

# --- oh-my-zsh (only if explicitly wanted in dotty.conf) ---
if [ "$WANT_OH_MY_ZSH" = "yes" ] && [ ! -d "$HOME/.oh-my-zsh" ]; then
  if have zsh && have curl; then
    info "installing oh-my-zsh"
    RUNZSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    info "zsh or curl not available; skipping oh-my-zsh (re-run after installing them)"
  fi
fi

# --- nvm ---
if [ ! -d "$HOME/.nvm" ]; then
  if have curl; then
    info "installing nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash
  else
    info "curl not available; skipping nvm (re-run after installing it)"
  fi
fi

# --- expose the repo at ~/.dotty regardless of clone location ---
if [ "$DOTTY" != "$HOME/.dotty" ]; then
  if [ -e "$HOME/.dotty" ] && [ ! -L "$HOME/.dotty" ]; then
    warn "~/.dotty exists and is not a symlink; leaving it alone"
  elif [ "$(readlink "$HOME/.dotty" 2>/dev/null)" != "$DOTTY" ]; then
    ln -sfn "$DOTTY" "$HOME/.dotty"
    info "linked ~/.dotty -> $DOTTY"
  fi
fi
# legacy: keep ~/.dotfiles pointing at the same place so pre-rename shells,
# aliases, and muscle memory keep working
if [ ! -e "$HOME/.dotfiles" ]; then
  ln -sfn "$DOTTY" "$HOME/.dotfiles"
fi

# --- migrate: git config is no longer managed here (was git/gitconfig) ---
# Turn old dangling symlinks back into real files with their last content.
migrate_git_file() {
  local dst="$1" rel="$2" c
  { [ -L "$dst" ] && [ ! -e "$dst" ]; } || return 0
  case "$(readlink "$dst")" in */"$rel") ;; *) return 0 ;; esac
  rm "$dst"
  c="$(git -C "$DOTTY" rev-list -2 HEAD -- "$rel" | tail -1)"
  if [ -n "$c" ] && git -C "$DOTTY" show "$c:$rel" > "$dst" 2>/dev/null; then
    info "git config is no longer managed by dotty - $dst is a plain file again"
  else
    rm -f "$dst"
    info "removed dangling $dst (git config is no longer managed; recreate it manually)"
  fi
}
migrate_git_file "$HOME/.gitconfig" "git/gitconfig"
migrate_git_file "$HOME/.config/git/ignore" "git/ignore"

# --- symlinks ---
link zsh/zshrc          "$HOME/.zshrc"
link zsh/zprofile       "$HOME/.zprofile"
link bash/bashrc        "$HOME/.bashrc"
link bash/bash_profile  "$HOME/.bash_profile"
link ghostty/config     "$HOME/.config/ghostty/config"
link tmux/tmux.conf     "$HOME/.tmux.conf"

# --- tmux plugins (only if the conf uses tpm) ---
if grep -q "plugins/tpm" "$DOTTY/tmux/tmux.conf" 2>/dev/null && have git; then
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    info "installing tpm (tmux plugin manager)"
    git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
  # clone declared plugins directly - tpm's own installer needs a running server
  sed -n "s/^set -g @plugin ['\"]\([^'\"]*\)['\"].*/\1/p" "$DOTTY/tmux/tmux.conf" \
  | while IFS= read -r plug; do
      # TPM supports repo#tag; keep the tag out of both the URL and directory,
      # then check out that exact version while cloning.
      repo="${plug%%#*}"
      ref=""
      [ "$repo" = "$plug" ] || ref="${plug#*#}"
      dst="$HOME/.tmux/plugins/$(basename "$repo")"
      [ -d "$dst" ] && continue
      case "$repo" in *://*) url="$repo" ;; *) url="https://github.com/$repo" ;; esac
      info "installing tmux plugin $plug"
      # -c advice.detachedHead=false: cloning a #tag detaches HEAD by design
      if [ -n "$ref" ]; then
        git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$url" "$dst" \
          || warn "couldn't clone tmux plugin $plug"
      else
        git clone -q --depth 1 "$url" "$dst" || warn "couldn't clone tmux plugin $plug"
      fi
    done
fi

# Claude Code user-level skills
mkdir -p "$HOME/.claude/skills"
for lnk in "$HOME/.claude/skills"/*; do
  # sweep dangling skill links left by renames
  if [ -L "$lnk" ] && [ ! -e "$lnk" ]; then
    case "$(readlink "$lnk")" in
      "$DOTTY"/*|*dotfiles*|*dotty*) rm "$lnk"; info "removed stale skill link $(basename "$lnk")" ;;
    esac
  fi
done
for skill in "$DOTTY"/.claude/skills/*/; do
  [ -d "$skill" ] || continue
  dst="$HOME/.claude/skills/$(basename "$skill")"
  if [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "${skill%/}" ]; then
    ln -sfn "${skill%/}" "$dst"
    info "linked skill $(basename "$skill")"
  fi
done

# --- default shell ---
if have "$PREFERRED_SHELL"; then
  case "${SHELL:-}" in
    */"$PREFERRED_SHELL") ;;
    *) info "setting default shell to $PREFERRED_SHELL"; chsh -s "$(command -v "$PREFERRED_SHELL")" || warn "chsh failed; run it manually" ;;
  esac
fi
