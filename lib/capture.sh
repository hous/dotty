# dotty lib/capture.sh - package capture helpers, POSIX sh.
# Sourced by save.sh and init.sh with $DOTTY set to the repo root.

# macOS: re-dump the Brewfile from the live brew state.
capture_brewfile() {
  if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "==> dotty: dumping Brewfile"
    brew bundle dump --file="$DOTTY/Brewfile" --force
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
    echo "==> dotty: captured apt packages: $(printf '%s ' $NEW_PKGS)"
  fi
}
