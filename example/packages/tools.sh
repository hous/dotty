# dotty packages/tools.sh - standalone CLI tools that no package manager
# tracks (vendor curl installers into ~/.local/bin). Sourced by install.sh
# with have() and info() available; every line must guard with `have` so
# re-runs are no-ops.
#
# Examples (uncomment what you use):
# have claude || { info "installing Claude Code"; curl -fsSL https://claude.ai/install.sh | bash; }
# have codex  || { info "installing Codex";       curl -fsSL https://chatgpt.com/codex/install.sh | sh; }
#
# Agent plugin marketplaces work here too - guard on the list output:
# claude plugin marketplace list 2>/dev/null | grep -q "my-marketplace" \
#   || claude plugin marketplace add https://github.com/OWNER/REPO
