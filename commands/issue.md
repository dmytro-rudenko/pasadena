---
description: Take a GitHub issue into work through the Pasadena workflow
argument-hint: "<issue number>"
allowed-tools: Bash(gh issue view *), Bash(gh repo view *)
---

Take GitHub issue #$0 into work.

1. **No number.** When `$0` is empty or not a number, say the form is
   `/issue <number>`; run nothing.
2. **Read the issue.** Run
   `gh issue view $0 --json number,title,body,labels,state,url,comments`.
   When it fails, report the error and stop. When the issue is closed, say so
   and ask before going on.
3. **Start the workflow.** Use the `pasadena` skill with the issue as the
   request: its title, body, labels and comments are the user's intent, and
   its URL goes into the journal and the spec. Questions the issue leaves
   open go to the user as usual. The PR body carries `Closes #$0`.
