#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PYTHONPATH="$ROOT" python3 - <<'PY'
import sys

from bench.tui_policy import Done, Fail, Keys, NUDGE, Paste, Wait, decide

ASK = """ ☐ File name
Which file name should I use?
❯ 1. a.txt (Recommended)
     Write the file as a.txt
  2. b.txt
     Write the file as b.txt
  3. Type something.
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel"""

ASK2 = """ ☐ File name
Which file name should I use?
  1. a.txt
     Write the file as a.txt
❯ 2. b.txt (Recommended)
     Write the file as b.txt
  3. Type something.
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel"""

PLAN = """   Claude has written up a plan and is ready to execute. Would you like to proceed?
   ❯ 1. Yes, and switch to BYPASS PERMISSIONS (no further prompts) for this session
     2. Yes, manually approve edits
     3. Tell Claude what to change
        shift+tab to approve with this feedback"""

MENU = "❯ No, exit\n  Yes, I accept\nEnter to confirm · Esc to cancel"

IDLE = "✻ Crunched for 5s · done 4:32 PM\n❯ cat a.txt\n  ⏵⏵ bypass permissions on (shift+tab to cycle)"


def stop(message, background=()):
    return {"last_assistant_message": message, "background_tasks": list(background)}


rows = [
    ("picks the recommended option", (ASK, None, None, 0, 0.0), Keys("1")),
    ("picks the recommended option when it is not first", (ASK2, None, None, 0, 0.0), Keys("2")),
    ("approves the plan dialog", (PLAN, None, None, 0, 0.0), Keys("1")),
    ("confirms a bare menu with Enter", (MENU, None, None, 0, 0.0), Keys("Enter")),
    ("dialog wins over a pending stop", (ASK, stop("Done."), None, 0, 0.0), Keys("1")),
    ("idle screen without a stop waits", (IDLE, None, None, 0, 0.0), Wait()),
    ("stop with background tasks waits before the limit", (IDLE, stop("Done.", ["x"]), None, 0, 10.0), Wait()),
    ("stop with background tasks is done after the limit", (IDLE, stop("Done.", ["x"]), None, 0, 600.0), Done()),
    ("question on the last line is nudged", (IDLE, stop("Spec written.\nShall I continue?"), None, 0, 0.0), Paste(NUDGE)),
    ("nudges are capped", (IDLE, stop("Spec written.\nShall I continue?"), None, 5, 0.0), Done()),
    ("ask phrase without a question mark is nudged", (IDLE, stop("Spec saved. Let me know when ready."), None, 0, 0.0), Paste(NUDGE)),
    ("question mark before the last line is not an ask", (IDLE, stop("Is it fast? Yes.\nAll tests pass."), None, 0, 0.0), Done()),
    ("plain completion is done", (IDLE, stop("All tests pass."), None, 0, 0.0), Done()),
    ("failure reports its error", (IDLE, None, {"error": "rate_limit"}, 0, 0.0), Fail("rate_limit")),
    ("failure beats a dialog", (ASK, None, {"error": "rate_limit"}, 0, 0.0), Fail("rate_limit")),
    ("failure without an error is StopFailure", (IDLE, None, {}, 0, 0.0), Fail("StopFailure")),
]

failures = 0
for name, args, expected in rows:
    actual = decide(*args)
    if actual == expected:
        print(f"  ok  — {name}")
    else:
        print(f"  FAIL — {name}: expected {expected!r}, got {actual!r}")
        failures += 1

sys.exit(failures)
PY
fails=$?

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
