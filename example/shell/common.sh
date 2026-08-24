# Shared environment + aliases - POSIX sh, sourced by BOTH zshrc and bashrc.
# Anything here must work in every supported shell; shell-specific config
# belongs in zsh/zshrc or bash/bashrc.

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- nvm ---
# --no-use skips nvm's startup `nvm use default`, which costs ~10s per shell;
# resolve the default version from the alias files and set PATH ourselves.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  \. "$NVM_DIR/nvm.sh" --no-use
  _v="$(cat "$NVM_DIR/alias/default" 2>/dev/null || echo node)" _i=0
  while [ -f "$NVM_DIR/alias/$_v" ] && [ "$_i" -lt 5 ]; do
    _v="$(cat "$NVM_DIR/alias/$_v")" _i=$((_i + 1))
  done
  if [ ! -d "$NVM_DIR/versions/node/$_v" ]; then
    # alias didn't resolve to an installed version (e.g. lts/*): newest wins
    _v="$(ls "$NVM_DIR/versions/node" 2>/dev/null | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1)"
  fi
  if [ -n "$_v" ] && [ -d "$NVM_DIR/versions/node/$_v/bin" ]; then
    export PATH="$NVM_DIR/versions/node/$_v/bin:$PATH"
  fi
  unset _v _i
fi

# --- aliases ---
alias python="python3"
alias pip="pip3"

# dotty - dotpull pulls latest + reinstalls; dotpush pushes this machine's changes
alias dotpull='~/.dotty/bootstrap.sh && exec "$SHELL"'
alias dotpush="~/.dotty/save.sh"

command -v eza >/dev/null 2>&1 && alias l="eza --long --color-scale"
