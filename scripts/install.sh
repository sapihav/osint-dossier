#!/usr/bin/env bash
# install.sh — install every CLI the osint-dossier skill expects.
#
# Idempotent in the "skip already-present" sense: re-running is safe and
# tools already on PATH are skipped. It does NOT detect or upgrade stale
# versions — to upgrade, uninstall the binary and re-run, or use each
# tool's native upgrade command.
#
# Public sources only:
#   - Go CLIs: curl|bash from each repo's install.sh on the `main` branch.
#     Trust model: those repos are owned by the same author as this skill;
#     anything pushed to their `main` runs verbatim on every install.
#     Pin to a release tag if you need a tighter trust boundary.
#   - npm and pipx packages: standard public registries.
#
# Modes:
#   bash install.sh                 install all missing tools
#   bash install.sh --check         report status; do not install (exit 1 if any missing)
#   bash install.sh --line <name>   print the install command for <name>; exit 0
#                                   exits 2 if <name> is unknown to this script

set -euo pipefail

# Tool registry. Each entry: bin|method|target
#   method ∈ curl | npm | pipx
#   target is whatever the method consumes:
#     curl → URL to a bash installer script (piped to bash)
#     npm  → npm package name
#     pipx → PyPI package name
TOOLS=(
  "perplexity|curl|https://raw.githubusercontent.com/sapihav/perplexity-cli/main/install.sh"
  "exa|curl|https://raw.githubusercontent.com/sapihav/exa-cli/main/install.sh"
  "tavily|curl|https://raw.githubusercontent.com/sapihav/tavily-cli/main/install.sh"
  "parallel-cli|curl|https://parallel.ai/install.sh"
  "apify|npm|apify-cli"
  "brightdata|npm|@brightdata/cli"
  "jina|pipx|jina"
)

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# Resolve a registry row by binary name. Echoes "method|target" or empty.
lookup() {
  local needle="$1" row bin
  for row in "${TOOLS[@]}"; do
    bin="${row%%|*}"
    if [ "$bin" = "$needle" ]; then
      printf '%s\n' "${row#*|}"
      return 0
    fi
  done
  return 1
}

# Print the install command for one binary.
install_line() {
  local bin="$1" rest method target
  if ! rest=$(lookup "$bin"); then
    return 2
  fi
  method="${rest%%|*}"
  target="${rest#*|}"
  case "$method" in
    curl) printf 'curl -sSL %s | bash\n' "$target" ;;
    npm)  printf 'npm install -g %s\n' "$target" ;;
    pipx) printf 'pipx install %s\n' "$target" ;;
    *)    warn "install.sh: unknown method '$method' for '$bin'"; return 2 ;;
  esac
}

# Verify the toolchain a method needs is on PATH. Returns 0 if usable.
toolchain_ok() {
  local method="$1"
  case "$method" in
    curl) command -v curl >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 ;;
    npm)  command -v npm  >/dev/null 2>&1 ;;
    pipx) command -v pipx >/dev/null 2>&1 ;;
    *)    return 1 ;;
  esac
}

# Print a one-time hint for installing a missing toolchain.
toolchain_hint() {
  case "$1" in
    curl) say "  hint: install curl  → brew install curl" ;;
    npm)  say "  hint: install Node  → brew install node" ;;
    pipx) say "  hint: install pipx  → brew install pipx && pipx ensurepath" ;;
  esac
}

# Run the install for one row. Returns 0 on success, non-zero otherwise.
do_install() {
  local bin="$1" method="$2" target="$3"
  case "$method" in
    curl) curl -sSL "$target" | bash ;;
    npm)  npm install -g "$target" ;;
    pipx) pipx install "$target" ;;
    *)    warn "install.sh: unknown method '$method'"; return 1 ;;
  esac
}

mode_line() {
  local bin="${1:-}"
  if [ -z "$bin" ]; then
    warn "Usage: install.sh --line <bin>"; return 2
  fi
  install_line "$bin"
}

mode_check() {
  local row bin missing=0
  say "=== osint-dossier — install status ==="
  for row in "${TOOLS[@]}"; do
    bin="${row%%|*}"
    if command -v "$bin" >/dev/null 2>&1; then
      say "  ✓  $bin"
    else
      say "  ✗  $bin   ($(install_line "$bin"))"
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    say ""
    say "$missing tool(s) missing. Run: bash scripts/install.sh"
    return 1
  fi
  return 0
}

mode_install() {
  local row bin method target installed=0 skipped=0 failed=0
  local needed_toolchains=()

  # Pass 1: check toolchains for tools that actually need installing.
  for row in "${TOOLS[@]}"; do
    bin="${row%%|*}"
    if command -v "$bin" >/dev/null 2>&1; then
      continue
    fi
    method="${row#*|}"; method="${method%%|*}"
    if ! toolchain_ok "$method"; then
      case " ${needed_toolchains[*]:-} " in
        *" $method "*) ;;
        *) needed_toolchains+=("$method") ;;
      esac
    fi
  done

  if [ "${#needed_toolchains[@]}" -gt 0 ]; then
    warn "install.sh: missing required toolchain(s): ${needed_toolchains[*]}"
    for tc in "${needed_toolchains[@]}"; do toolchain_hint "$tc" >&2; done
    warn ""
    warn "Install the toolchain(s) above, then re-run: bash scripts/install.sh"
    return 1
  fi

  # Pass 2: install missing tools.
  say "=== osint-dossier — installing CLIs ==="
  for row in "${TOOLS[@]}"; do
    bin="${row%%|*}"; method="${row#*|}"; method="${method%%|*}"
    target="${row##*|}"
    if command -v "$bin" >/dev/null 2>&1; then
      say "  ✓  $bin (already installed)"
      skipped=$((skipped + 1))
      continue
    fi
    say "  →  $bin   $(install_line "$bin")"
    if do_install "$bin" "$method" "$target"; then
      installed=$((installed + 1))
    else
      warn "  ✗  $bin failed to install"
      failed=$((failed + 1))
    fi
  done

  say ""
  say "Installed: $installed   Skipped: $skipped   Failed: $failed"

  if [ "$failed" -gt 0 ]; then return 1; fi
  return 0
}

case "${1:-}" in
  --line)  shift; mode_line "${1:-}"; exit $? ;;
  --check) mode_check; exit $? ;;
  -h|--help)
    cat <<'EOF'
Usage: install.sh [--check | --line <bin>]

  (no args)         install every missing CLI the skill expects
  --check           report status only; non-zero exit if any missing
  --line <bin>      print the install command for <bin>

Tools installed: perplexity, exa, tavily (curl | bash from each repo's
                 install.sh, fetches the latest GitHub release binary);
                 apify, brightdata (npm); jina (pipx). Public sources only.
EOF
    exit 0 ;;
  "")      mode_install; exit $? ;;
  *)       warn "install.sh: unknown arg '$1' (try --help)"; exit 2 ;;
esac
