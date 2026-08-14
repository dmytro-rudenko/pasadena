#!/usr/bin/env bash
# Self-check for the prototype server. Run: bash proto/server.test.sh
# Needs: node, curl.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fails=0

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected substring: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

assert_equals() {
  if [ "$1" = "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

# A content dir with one screen, plus a secret one level up that a traversal
# would reach if the resolver were sloppy.
setup_dirs() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/content" "$d/state"
  printf 'top secret\n' >"$d/secret.txt"
  cat >"$d/content/screen.html" <<'EOF'
<!doctype html><html><body>
<div class="options"><div class="option" data-choice="a"><span class="letter">A</span>Alpha</div></div>
</body></html>
EOF
  printf '%s' "$d"
}

start() {
  bash "$DIR/start.sh" --content-dir "$1/content" --state-dir "$1/state" 2>/dev/null
}

echo "== prototype server =="

d="$(setup_dirs)"
started="$(start "$d")"
assert_contains "$started" '"type":"server-started"' "start.sh prints the startup line"

url="$(printf '%s' "$started" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
base="${url%%\?*}"
base="${base%/}"   # so "$base/_sdd/..." is not a double slash
key="${url##*key=}"

code="$(curl -s -o /dev/null -w '%{http_code}' "$base")"
assert_equals "$code" "403" "a request with no key is refused"

body="$(curl -s "$base?key=$key")"
assert_contains "$body" "Alpha" "a keyed request serves the newest screen at /"
assert_contains "$body" "/_sdd/client.js" "the client script is injected into served HTML"

code="$(curl -s -o /dev/null -w '%{http_code}' "$base?key=wrong")"
assert_equals "$code" "403" "a wrong key is refused"

# The cookie the first keyed response set must carry the next request alone.
jar="$d/cookies"
curl -s -c "$jar" -o /dev/null "$base?key=$key"
css="$(curl -s -b "$jar" "$base/_sdd/frame.css")"
assert_contains "$css" "--selected-border" "the cookie alone authorizes a subresource"

# ../ must not escape the content dir, encoded or not. --path-as-is on both:
# without it curl collapses the ".." itself and the server never sees it.
code="$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$base/../secret.txt?key=$key")"
assert_equals "$code" "404" "a traversal above the content dir is refused"
code="$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$base/%2e%2e/secret.txt?key=$key")"
assert_equals "$code" "404" "an encoded traversal is refused too"

# A click becomes one JSONL line with a server-side timestamp.
curl -s -o /dev/null -X POST "$base/_sdd/event?key=$key" \
  -H 'content-type: application/json' \
  -d '{"type":"click","choice":"a","text":"Alpha"}'
events="$(cat "$d/state/events" 2>/dev/null)"
assert_contains "$events" '"choice":"a"' "a click lands in the events file"
assert_contains "$events" '"ts":' "the server stamps the event with a time"
assert_equals "$(wc -l <"$d/state/events")" "1" "one click is exactly one line"

# The poll stamp is what makes the open tab reload.
before="$(curl -s "$base/_sdd/poll?key=$key")"
sleep 1
printf '<!doctype html><html><body>Beta</body></html>\n' >"$d/content/screen-v2.html"
after="$(curl -s "$base/_sdd/poll?key=$key")"
if [ "$before" != "$after" ]; then
  echo "  ok  — writing a screen moves the poll stamp"
else
  echo "  FAIL — writing a screen moves the poll stamp"
  echo "        stamp did not change: $before"
  fails=$((fails + 1))
fi

body="$(curl -s "$base?key=$key")"
assert_contains "$body" "Beta" "/ follows the newest screen"

stopped="$(bash "$DIR/stop.sh" --state-dir "$d/state")"
assert_contains "$stopped" '"stopped":true' "stop.sh kills the server"
sleep 0.3
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$base?key=$key" || true)"
assert_equals "$code" "000" "nothing answers on the port afterwards"

rm -rf "$d"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
