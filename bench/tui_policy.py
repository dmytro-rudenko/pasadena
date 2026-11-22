import re
from dataclasses import dataclass

MAX_NUDGES = 5
BACKGROUND_WAIT_S = 600
NUDGE = (
    "No human is available to answer. Take that as approval: continue with the "
    "recommended option until the task is finished and verified."
)
ASK_PHRASES = (
    "let me know",
    "tell me",
    "your approval",
    "approve",
    "would you like",
    "shall i",
    "should i",
    "ready to proceed",
    "before we move on",
    "before i continue",
)
RECOMMENDED = re.compile(r"^\s*(?:❯\s*)?(\d+)\.\s.*\(Recommended\)", re.M)


@dataclass(frozen=True)
class Keys:
    keys: str


@dataclass(frozen=True)
class Paste:
    text: str


@dataclass(frozen=True)
class Wait:
    pass


@dataclass(frozen=True)
class Done:
    pass


@dataclass(frozen=True)
class Fail:
    reason: str


def asks(message):
    lines = [line for line in message.splitlines() if line.strip()]
    lowered = message.lower()
    return bool(lines and "?" in lines[-1]) or any(p in lowered for p in ASK_PHRASES)


def decide(screen, stop, failure, nudges, idle_s):
    if failure is not None:
        return Fail(str(failure.get("error") or "StopFailure"))
    match = RECOMMENDED.search(screen)
    if match:
        return Keys(match.group(1))
    if "Would you like to proceed?" in screen:
        return Keys("1")
    if "Enter to select" in screen or "Enter to confirm" in screen:
        return Keys("Enter")
    if stop is None:
        return Wait()
    if stop.get("background_tasks") and idle_s < BACKGROUND_WAIT_S:
        return Wait()
    if asks(stop.get("last_assistant_message") or "") and nudges < MAX_NUDGES:
        return Paste(NUDGE)
    return Done()
