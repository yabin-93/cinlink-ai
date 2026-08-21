# Test Stage

Use this reference only for running or rerunning CinLink tests.

## Entry points

Run from the repository root:

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -All
& ".\tools\run-cinlink-test-stage.ps1" -Workflow "subtitle"
& ".\tools\run-cinlink-test-stage.ps1" -CaseId "CL-AI-010"
```

Use `-DryRun` to validate selection and view prompts without restarting CinLink or submitting tasks. Use `-NoRestart` only when CinLink is already listening on the expected CDP port.

Exactly one of `-All`, `-Workflow`, or `-CaseId` is required. Workflows are `subtitle`, `translation`, `enhance`, `text-watermark`, `image-watermark`, `mix`, and `long-to-short`.

## Execution contract

1. Confirm the selected scope and source case file.
2. Run the stage-one entrypoint.
3. For serial runs, honor the manual gate between tasks so credit and status evidence do not overlap.
4. Report the absolute run-directory path.
5. Inspect `run-manifest.json`, `execution-observations.json`, `smoke-test-report.md`, screenshots, downloads, and diagnostics.

Stage one never calls Yunxiao. A `submitted` state proves only that the task was submitted, not that the case passed.

## Review handoff

After results are final, group failed cases by root cause. Create or update `<run-directory>/yunxiao-defects.json` only with confirmed product defects. Keep runner defects out of the CinLink product list. Each defect must include its stable key, severity, subject, aliases, Job IDs, steps, actual and expected results, impact, and evidence filenames.
