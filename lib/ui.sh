# dotty lib/ui.sh - one voice for every script's output. POSIX sh, sourced.
# Draws colored dots when the locale can render them, plain "==> dotty:" ASCII
# otherwise; color only on a TTY (and never when NO_COLOR is set).
# bootstrap.sh carries its own inline copy of this block (it must run
# standalone via curl|sh before the repo exists) - keep the two in sync.

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]*8*) DOT='●' DOT_OPEN='○' DOTS='●●●' SEP=' ·' ;;
  *)                DOT='*' DOT_OPEN='o' DOTS='==>' SEP=':' ;;
esac
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK='\033[1;32m' C_INFO='\033[1;34m' C_WARN='\033[1;33m' C_DIM='\033[2m' C_OFF='\033[0m'
else
  C_OK='' C_INFO='' C_WARN='' C_DIM='' C_OFF=''
fi

# info MSG - routine progress (blue dots)      ●●● dotty · installing nvm
# ok MSG   - a happy outcome (green dots)      ●●● dotty · dots pushed
# warn MSG - needs the user (yellow, stderr)   ●●● dotty · that looks like a secret
# item LABEL VALUE      - detail line, filled dot:  ● packages  eza ripgrep
# item_open LABEL VALUE - detail line, open dot:    ○ changed   ghostty/config
info() { printf "${C_INFO}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*"; }
ok()   { printf "${C_OK}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*"; }
warn() { printf "${C_WARN}%s${C_OFF} dotty${C_DIM}%s${C_OFF} %s\n" "$DOTS" "$SEP" "$*" >&2; }
item()      { printf "  ${C_OK}%s${C_OFF} %-9s %s\n" "$DOT" "$1" "$2"; }
item_open() { printf "  ${C_DIM}%s${C_OFF} %-9s %s\n" "$DOT_OPEN" "$1" "$2"; }
