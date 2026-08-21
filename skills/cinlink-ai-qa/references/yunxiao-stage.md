# Yunxiao Stage

Use this reference only after the selected run has a reviewed `yunxiao-defects.json`.

## Preview

Always start with:

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory "<absolute-or-reviewed-run-directory>" `
  -DryRun
```

Confirm the displayed run ID, defect count, titles, evidence paths, assignee, project, and deduplication aliases. Tell the user how many entries are expected to be created, updated, or skipped when that information is available.

DryRun does not authorize a real write. Ask for explicit confirmation after showing the preview.

## Write and verify

After confirmation, run:

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory "<same-reviewed-run-directory>" `
  -ConfirmWrite
```

The lower-level synchronizer queries existing Bugs before creating anything, matches exact subjects and configured aliases, uploads missing evidence, embeds permanent image links, and reads each work item back.

Report created, updated, and idempotently skipped work items with their direct Yunxiao links. If the write or readback fails, preserve the result/error JSON and stop. Do not create a replacement work item merely because a query, upload, or update failed.

## Repeat runs

Reusing the same run directory and defect keys must not create duplicates. A completed repeat should report zero creates and zero updates with all entries idempotently skipped. Any different result requires inspection before another write.
