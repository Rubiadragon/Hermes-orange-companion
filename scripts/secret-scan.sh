#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

EXCLUDES=(
  --hidden
  --glob '!.git/**'
  --glob '!*.png'
  --glob '!*.jpg'
  --glob '!*.jpeg'
  --glob '!*.m4a'
  --glob '!*.mov'
  --glob '!*.mp4'
  --glob '!*.gif'
  --glob '!*.dmg'
  --glob '!*.zip'
)

HIGH_CONFIDENCE_PATTERN='sk-proj-[A-Za-z0-9_-]{20,}|sk-svcacct-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |OPENSSH |EC |DSA |PRIVATE )?PRIVATE KEY-----'
GENERIC_PATTERN='api[_-]?key|secret|token|password|authorization|bearer|\.env|config\.yaml|private[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token'
HIGH_ENTROPY_PATTERN='[A-Za-z0-9_+/=-]{80,}|[0-9a-fA-F]{64,}'

fail=0

print_section() {
  printf '\n== %s ==\n' "$1"
}

scan_files() {
  local label="$1"
  local pattern="$2"
  print_section "$label"
  local matches
  matches="$(rg --no-config --files-with-matches -I "${EXCLUDES[@]}" -e "$pattern" . || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
    return 1
  fi
  printf 'No matches.\n'
  return 0
}

print_section "Suspicious File Names"
suspicious_files="$(find . -path ./.git -prune -o -type f \( \
  -name '.env' -o \
  -name '.env.*' -o \
  -name '*.pem' -o \
  -name '*.key' -o \
  -name '*.p8' -o \
  -name '*.p12' -o \
  -name '*.mobileprovision' -o \
  -name '*credentials*' -o \
  -name '*secret*' -o \
  -name '*token*' \
\) ! -path './scripts/secret-scan.sh' -print)"
if [[ -n "$suspicious_files" ]]; then
  printf '%s\n' "$suspicious_files"
  fail=1
else
  printf 'No matches.\n'
fi

if ! scan_files "High Confidence Secret Shapes" "$HIGH_CONFIDENCE_PATTERN"; then
  fail=1
fi

print_section "Generic Secret References"
generic_matches="$(rg --no-config --files-with-matches -I "${EXCLUDES[@]}" -i -e "$GENERIC_PATTERN" . || true)"
if [[ -n "$generic_matches" ]]; then
  printf '%s\n' "$generic_matches"
else
  printf 'No matches.\n'
fi

print_section "High Entropy Strings"
entropy_matches="$(rg --no-config --files-with-matches -I "${EXCLUDES[@]}" -e "$HIGH_ENTROPY_PATTERN" . || true)"
if [[ -n "$entropy_matches" ]]; then
  printf '%s\n' "$entropy_matches"
  printf 'Review these manually. Package checksums and Sparkle signatures can be expected false positives.\n'
else
  printf 'No matches.\n'
fi

print_section "Git History High Confidence Secret Shapes"
history_matches="$(git grep -I -l -E "$HIGH_CONFIDENCE_PATTERN" $(git rev-list --all) 2>/dev/null || true)"
if [[ -n "$history_matches" ]]; then
  printf '%s\n' "$history_matches"
  fail=1
else
  printf 'No matches.\n'
fi

if [[ "$fail" -ne 0 ]]; then
  printf '\nSecret scan failed. Review high-confidence matches before publishing.\n'
  exit 1
fi

printf '\nSecret scan passed. Generic references and high-entropy false positives may still need human review.\n'
