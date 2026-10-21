# dotty lib/capture.sh - package capture helpers, POSIX sh.
# Sourced by save.sh and init.sh with $DOTTY set to the repo root.
. "$DOTTY/lib/ui.sh"

# macOS: re-dump the Brewfile from the live brew state.
capture_brewfile() {
  if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    info "dumping Brewfile"
    brew bundle dump --file="$DOTTY/Brewfile" --force
  fi
}

# Rust: crates installed with `cargo install` on this machine. Appends new
# ones to packages/cargo.txt (never prunes: an absent crate may just be
# uninstalled here).
capture_cargo_packages() {
  CARGO="$(command -v cargo 2>/dev/null || true)"
  [ -n "$CARGO" ] || [ ! -x "$HOME/.cargo/bin/cargo" ] || CARGO="$HOME/.cargo/bin/cargo"
  [ -n "$CARGO" ] || return 0
  mkdir -p "$DOTTY/packages"
  touch "$DOTTY/packages/cargo.txt"
  # One line per crate: "name" (crates.io) or "name --git <url>". Lines are
  # passed to `cargo install` verbatim.
  NEW_CRATES="$("$CARGO" install --list 2>/dev/null | awk '
    /^[^ ]/ {
      name=$1; src=""
      if ($3 ~ /^\(https?:\/\//) { src=$3; sub(/^\(/,"",src); sub(/[#)].*$/,"",src) }
      if (src != "") print name " --git " src; else print name
    }' | sort -u | grep -Fxvf "$DOTTY/packages/cargo.txt" || true)"
  if [ -n "$NEW_CRATES" ]; then
    printf '%s\n' "$NEW_CRATES" >> "$DOTTY/packages/cargo.txt"
    info "captured cargo crates:$(printf '%s\n' "$NEW_CRATES" | awk '{printf " %s", $1}')"
  fi
}

# Debian/Ubuntu: capture packages a human explicitly installed (apt history
# marks those with Requested-By), skipping lib/dev noise and version pins.
# Appends new ones to packages/apt.txt, honoring packages/apt-ignore.txt.
capture_apt_packages() {
  command -v apt-get >/dev/null 2>&1 || return 0
  [ -r /var/log/apt/history.log ] || return 0
  mkdir -p "$DOTTY/packages"
  touch "$DOTTY/packages/apt.txt" "$DOTTY/packages/apt-ignore.txt"
  NEW_PKGS="$(zcat -f /var/log/apt/history.log* 2>/dev/null | awk -v user="$(id -un)" '
    /^Start-Date:/{cmd="";req=""}
    /^Commandline:/{cmd=$0}
    /^Requested-By:/{req=$0}
    /^End-Date:/{
      if (req ~ user && cmd ~ /apt(-get)? +(-[^ ]+ +)*install /) {
        sub(/.*install +/,"",cmd)
        n=split(cmd,a," ")
        for(i=1;i<=n;i++) if (a[i] !~ /^-/ && a[i] !~ /\//) { sub(/=.*/,"",a[i]); print a[i] }
      }
    }' | grep -vE '^lib|-dev$|-dbg$' | sort -u \
       | grep -Fxvf "$DOTTY/packages/apt.txt" \
       | grep -Fxvf "$DOTTY/packages/apt-ignore.txt" || true)"
  if [ -n "$NEW_PKGS" ]; then
    printf '%s\n' $NEW_PKGS >> "$DOTTY/packages/apt.txt"
    info "captured apt packages: $(printf '%s ' $NEW_PKGS)"
  fi

  # Capture removals too: a listed package that is gone from this machine and
  # that dpkg or apt history shows being removed (not one that merely never
  # installed here) is pruned from apt.txt and pinned in apt-ignore.txt so no
  # machine's dotpush re-captures it.
  REMOVED_LOG="$(zcat -f /var/log/apt/history.log* 2>/dev/null | awk -v user="$(id -un)" '
    /^Start-Date:/{cmd="";req=""}
    /^Commandline:/{cmd=$0}
    /^Requested-By:/{req=$0}
    /^End-Date:/{
      if (req ~ user && cmd ~ /apt(-get)? +(-[^ ]+ +)*(remove|purge|autoremove) /) {
        sub(/.*(remove|purge|autoremove) +/,"",cmd)
        n=split(cmd,a," ")
        for(i=1;i<=n;i++) if (a[i] !~ /^-/ && a[i] !~ /\//) { sub(/=.*/,"",a[i]); print a[i] }
      }
    }' | sort -u)"
  PRUNED="$(while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      st="$(dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null || true)"
      case "$st" in
        "install ok installed") continue ;;                          # still here: keep
        deinstall*) printf '%s\n' "$pkg"; continue ;;                # apt remove'd
        "unknown ok not-installed") printf '%s\n' "$pkg"; continue ;; # purged (dpkg remembers it)
      esac
      # no dpkg trace at all: prune only with an apt-history removal to show for it
      printf '%s\n' "$REMOVED_LOG" | grep -Fxq "$pkg" && printf '%s\n' "$pkg"
    done < "$DOTTY/packages/apt.txt" || true)"
  if [ -n "$PRUNED" ]; then
    TMP="$DOTTY/packages/apt.txt.tmp"
    printf '%s\n' "$PRUNED" | grep -Fxvf - "$DOTTY/packages/apt.txt" > "$TMP" || true
    mv "$TMP" "$DOTTY/packages/apt.txt"
    printf '%s\n' "$PRUNED" | grep -Fxvf "$DOTTY/packages/apt-ignore.txt" - >> "$DOTTY/packages/apt-ignore.txt" || true
    info "pruned apt packages removed here:$(printf ' %s' $PRUNED)"
  fi
}
