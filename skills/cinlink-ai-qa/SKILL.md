---
name: cinlink-ai-qa
description: Use when running CinLink AI workflow tests, reviewing CinLink run evidence, rerunning a workflow or case, or synchronizing reviewed CinLink defects and attachments to Yunxiao.
---

# CinLink AI QA

Keep test execution and Yunxiao synchronization as separate stages. Announce the selected stage before acting.

## Route the request

| User intent | Action |
|---|---|
| Run all tests, one workflow, or one case | Read [references/test-stage.md](references/test-stage.md); run only stage one. |
| Review a run or prepare defects | Inspect local evidence and prepare `yunxiao-defects.json`; do not write Yunxiao. |
| Sync reviewed defects to Yunxiao | Read [references/yunxiao-stage.md](references/yunxiao-stage.md); preview first. |
| Run tests and sync defects | Finish stage one, then stop for human defect review and separate write authorization. |
| Commit or push to GitHub | Provide manual commands or a changed-file list only. |

## Invariants

- Use the repository scripts; do not reproduce CDP or Yunxiao API logic manually.
- A failed test is not automatically a product defect. Merge failures with the same root cause during review.
- Treat the run directory's `yunxiao-defects.json` as the only approved input to stage two.
- A Yunxiao `DryRun` preview and explicit user confirmation are required before `-ConfirmWrite`.
- Stop if duplicate lookup finds multiple possible work items or if readback verification fails.
- Never run Git mutation commands. Git add, commit, push, and pull-request creation remain manual.
- Never expose or store Yunxiao tokens; use the existing environment/DPAPI credential path.

## Common mistakes

- Do not infer that “run all tests” authorizes Yunxiao writes.
- Do not select the newest run silently when more than one plausible run exists; show the path being used.
- Do not bypass preview because a batch was synchronized previously; the reviewed file may have changed.
- Do not resubmit after a timeout unless the test procedure explicitly authorizes retry.
