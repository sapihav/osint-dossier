#!/usr/bin/env bash
# _slug.sh — single source of truth for the osint-dossier subject-slug recipe.
# Sourced by first-volley.sh and check-tools.sh; not executable as a CLI.
#
# slug_from <subject>
#   stdout: lowercase ASCII slug, hyphens for runs of non-alnum, leading/
#           trailing hyphens stripped. Empty string if subject collapses.
#   stderr: silent.
#   return: 0 always (caller decides how to treat empty slug).

slug_from() {
  printf '%s' "${1:-}" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9' '-' \
    | sed 's/--*/-/g; s/^-//; s/-$//'
}
