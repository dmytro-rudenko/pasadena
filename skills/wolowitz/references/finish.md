# Whole-branch review dispatch

Fill `reviewer-prompt.md` for the whole branch — the merge-base as
`BASE`, the plan's path, every task number, waves `0`–`<last>` as
`<a>`–`<b>`, the spec's path. When `codex.sh available` exits 0 outside
full mode, write a
Codex copy to a prompt file in the scratchpad, replacing the `**The diff:**` line with: the
diff arrives on stdin as a `<stdin>` block — review that diff; read local
files only for context. Keep "Do not re-run the tests". Run
`codex.sh review $(git merge-base origin/<trunk> HEAD) <prompt-file>` in the
background in the same message as the `sonnet` dispatch. Every `sonnet`
finding goes to the fix wave. A Codex finding goes there only after you
confirm it at its `file:line`; drop the unconfirmed ones with a
one-line note in the final PR comment. The `sonnet` verdict stays the
verdict. The final PR comment carries the review's `codex usage:` line.
Decide every `Declined to judge` item from either review yourself, as in
step 4 of the wave loop, in the final PR comment.
