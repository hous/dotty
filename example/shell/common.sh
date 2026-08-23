# Shared environment + aliases - POSIX sh, sourced by BOTH zshrc and bashrc.
# Anything here must work in every supported shell; shell-specific config
# belongs in zsh/zshrc or bash/bashrc.

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- nvm ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# --- aliases ---
alias python="python3"
alias pip="pip3"

# dotty - dotpull pulls latest + reinstalls; dotpush pushes this machine's changes
alias dotpull='~/.dotty/bootstrap.sh && exec "$SHELL"'
alias dotpush="~/.dotty/save.sh"

command -v eza >/dev/null 2>&1 && alias l="eza --long --color-scale"
