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
2. Run the stage-one entrypoint in its default `Hybrid` mode. Do not substitute Playwright.
3. Let repository scripts submit each case and let the CDP terminal gate finish before the next case is submitted.
4. For cases with `manualActions`, use the Open Computer Use snapshot and complete the displayed desktop-action gate before terminal polling continues.
5. Use ffprobe validation when a result artifact has a local filesystem path; record `no-local-artifact` when it does not.
6. Report the absolute run-directory path.
7. Inspect `run-manifest.json`, `execution-observations.json`, `smoke-test-report.md`, screenshots, downloads, and diagnostics.

Stage one never calls Yunxiao. A `submitted` state proves only that the task was submitted, not that the case passed.

The run manifest records `executionMode: hybrid` and the concrete strategy: repository-script submission, CDP terminal gate, Open Computer Use desktop actions, ffprobe media validation, Pester script tests, and disabled browser automation.

## Review handoff

After results are final, group failed cases by root cause. Create or update `<run-directory>/yunxiao-defects.json` only with confirmed product defects. Keep runner defects out of the CinLink product list. Each defect must include its stable key, severity, subject, aliases, Job IDs, steps, actual and expected results, impact, and evidence filenames.
