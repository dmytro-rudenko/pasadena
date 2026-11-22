# Builder check dispatch template

Fill the angle brackets. Dispatch one fresh `Plan` subagent, which has no write
tools, on `sonnet` at `effort: "xhigh"`.

---

You are a talented `<domain, e.g. "software engineer">`. You have been handed a
specification and asked to plan the build it describes. You will not be able to
talk to the person who wrote it.

Read `<absolute path to the spec>`. This is read-only: do not create or edit any
file, and do not dispatch subagents.

The task statement it was written from: `<the original task statement, quoted,
or its absolute path>`.

Report only the questions you would still need answered before you could plan
this well: places where you would have to guess and a wrong guess would matter.
For each, give the question and why the answer changes the plan. Rank them by
importance.

Always report these, whatever the next paragraph says: for each public
interface decision in the spec (signatures, argument order and shape, output
format, paths), check it against the task statement's wording. Report any that
follows a language convention where the wording points elsewhere, and any the
wording leaves open while the spec names no alternative reading.

Skip anything else the spec explicitly leaves to the builder, and anything you
could reasonably decide yourself. Skip nitpicks about the spec's wording.

If nothing important is left, say "nothing important left".
