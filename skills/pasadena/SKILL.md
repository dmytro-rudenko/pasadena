---
name: pasadena
description: Use when the user asks to start, resume, plan, or run a Pasadena spec-driven development workflow. Inspects the task journal and routes to the next workflow skill.
---

# Pasadena workflow

Use this skill as the entry point for the full Pasadena workflow.

1. Inspect the current branch, `.pasadena/journal/<branch>.md`, and then the
   legacy `.claude/journal/<branch>.md` only when the canonical file is absent.
2. Route by the persisted state:
   - journal absent: `sheldon`;
   - `spec: -`: `sheldon`;
   - `spec:` set and `plan: -`: `leonard`;
   - both set with unchecked plan tasks: `wolowitz`;
   - all tasks checked: `journal` with `finish`.
3. State the detected phase before continuing. Always resume persisted progress;
   the journal, plan checkboxes, and git log are the source of truth.
4. For a small one-session fix, let `sheldon` classify it before creating a
   journal. The resulting classification sets the appropriate amount of
   ceremony.
