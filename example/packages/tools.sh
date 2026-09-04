# dotty packages/tools.sh - standalone CLI tools that no package manager
# tracks (vendor curl installers into ~/.local/bin). Sourced by install.sh
# with have() and info() available; every line must guard with `have` so
# re-runs are no-ops.
#
# Examples (uncomment what you use):
# have claude || { info "installing Claude Code"; curl -fsSL https://claude.ai/install.sh | bash; }
# have codex  || { info "installing Codex";       curl -fsSL https://chatgpt.com/codex/install.sh | sh; }
