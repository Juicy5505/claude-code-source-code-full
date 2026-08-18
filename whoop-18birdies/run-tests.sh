#!/usr/bin/env bash
#
# Run every test in the project: TypeScript, Python, and the type checker.
#
#   ./run-tests.sh          everything
#   ./run-tests.sh --quick  skip the type check
#
# Exits non-zero if anything fails, so it works as a pre-push check or in CI.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

FAILED=0
say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
pass() { printf '    \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }

# --- TypeScript ---------------------------------------------------------------

say "TypeScript (bun test)"
if command -v bun >/dev/null 2>&1; then
  if OUT=$(bun test 2>&1); then
    pass "$(echo "$OUT" | grep -E '^\s*[0-9]+ pass' | tr -d '\n' | xargs)"
  else
    echo "$OUT" | tail -30
    fail "bun test"
  fi
else
  fail "bun not installed — see https://bun.sh"
fi

if [ "$QUICK" -eq 0 ]; then
  say "Type check (tsc --noEmit)"
  if command -v bunx >/dev/null 2>&1; then
    if OUT=$(bunx tsc --noEmit 2>&1); then
      pass "no type errors"
    else
      echo "$OUT" | head -30
      fail "tsc"
    fi
  else
    fail "bunx not available"
  fi
fi

# --- Python -------------------------------------------------------------------

say "Python (unittest)"
TOTAL=0
for file in iphone/test_*.py; do
  name=$(basename "$file")
  # Each suite runs from iphone/ so its sibling imports resolve without a
  # package install — the same way Pythonista runs them on the phone.
  if OUT=$(cd iphone && python3 "$name" 2>&1); then
    COUNT=$(echo "$OUT" | grep -oE '^Ran [0-9]+' | grep -oE '[0-9]+' || echo 0)
    TOTAL=$((TOTAL + COUNT))
    pass "$(printf '%-24s %s test(s)' "$name" "$COUNT")"
  else
    echo "$OUT" | tail -25
    fail "$name"
  fi
done
[ "$TOTAL" -gt 0 ] && printf '    \033[32m--\033[0m   %s python test(s) total\n' "$TOTAL"

# --- Xcode project ------------------------------------------------------------

say "Xcode project generates and validates"
if OUT=$(python3 watch/test_generate_project.py 2>&1); then
  COUNT=$(echo "$OUT" | grep -oE '^Ran [0-9]+' | grep -oE '[0-9]+' || echo 0)
  pass "$COUNT check(s) — parses as a plist, no dangling refs, settings correct"
else
  echo "$OUT" | tail -25
  fail "watch project"
fi

# --- Golden vectors -----------------------------------------------------------

say "Swift golden vectors are current"
if OUT=$(python3 iphone/gen_swing_vectors.py --check 2>&1); then
  pass "swing_vectors.json matches the Python reference"
else
  echo "$OUT"
  fail "regenerate with: python3 iphone/gen_swing_vectors.py"
fi

# --- Result -------------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll suites passed.\033[0m\n'
else
  printf '\033[31mSomething failed — see above.\033[0m\n'
fi
exit "$FAILED"
