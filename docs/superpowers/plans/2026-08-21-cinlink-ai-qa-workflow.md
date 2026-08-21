# CinLink AI QA Staged Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one reusable `cinlink-ai-qa` Skill with two independent, tested PowerShell entrypoints for running CinLink tests and synchronizing reviewed defects to Yunxiao.

**Architecture:** Keep the existing case runner and Yunxiao API implementation as lower-level engines. Add thin stage entrypoints that validate inputs and produce stable handoff behavior, then add a repository-managed Skill that routes natural-language requests to either stage without coupling them or performing Git operations.

**Tech Stack:** PowerShell 5.1-compatible scripts, JSON test and defect configuration, Codex Skill Markdown, existing Electron CDP tooling, Yunxiao OpenAPI.

**Spec:** `docs/superpowers/specs/2026-08-21-cinlink-ai-qa-workflow-design.md`

## Global Constraints

- Test execution and Yunxiao synchronization must remain independently invocable.
- Stage one must never create or update Yunxiao work items.
- Stage two must read only the reviewed `yunxiao-defects.json` from the selected run directory.
- Real Yunxiao writes require a successful preview and explicit user confirmation.
- Duplicate detection is by root cause, with stable run markers and attachment-name idempotency.
- GitHub synchronization is manual; no Skill or script may run `git add`, `git commit`, `git push`, or create a pull request.
- Secrets must come from an environment variable or the existing DPAPI credential cache and must never enter repository files or output logs.
- All PowerShell entrypoints must work in Windows PowerShell 5.1 and the current PowerShell runtime.

---

## File Structure

- Create `tools/run-cinlink-test-stage.ps1`: stable stage-one interface and run-directory handoff.
- Create `tools/tests/run-cinlink-test-stage.Tests.ps1`: stage-one parameter and DryRun behavior.
- Create `tools/sync-yunxiao-stage.ps1`: stable stage-two preview/write interface.
- Create `tools/tests/sync-yunxiao-stage.Tests.ps1`: stage-two directory, reviewed-config, and confirmation behavior.
- Create `skills/cinlink-ai-qa/SKILL.md`: natural-language router and safety boundaries.
- Create `skills/cinlink-ai-qa/references/test-stage.md`: detailed stage-one commands and output contract.
- Create `skills/cinlink-ai-qa/references/yunxiao-stage.md`: detailed preview, authorization, and readback workflow.
- Create `tools/install-cinlink-ai-qa-skill.ps1`: idempotently link the repository Skill into the user Skill directory.
- Create `tools/tests/install-cinlink-ai-qa-skill.Tests.ps1`: validate installation planning without modifying the real user Skill directory.
- Modify `README.md`: document the two stages, manual review boundary, Skill usage, installation, and manual Git workflow.

---

### Task 1: Add the Test Execution Stage Entrypoint

**Files:**
- Create: `tools/run-cinlink-test-stage.ps1`
- Create: `tools/tests/run-cinlink-test-stage.Tests.ps1`

**Interfaces:**
- Consumes: `tools/run-cinlink-cases.ps1` with exactly one selector from `-All`, `-Workflow <name>`, or `-CaseId <id>`, plus optional `-NoRestart` and `-DryRun`.
- Produces: a zero exit code and a final machine-readable JSON object with `stage`, `selector`, `dryRun`, and `runDirectory`; on real execution `runDirectory` is an absolute path.

- [ ] **Step 1: Write the failing stage-one tests**

Create `tools/tests/run-cinlink-test-stage.Tests.ps1` with controlled invocation through a temporary fake runner:

```powershell
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\run-cinlink-test-stage.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-test-stage-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $fakeRunner = Join-Path $fixtureRoot 'runner.ps1'
    @'
param([switch]$All, [string]$Workflow, [string]$CaseId, [switch]$NoRestart, [switch]$DryRun)
[pscustomobject]@{ All = [bool]$All; Workflow = $Workflow; CaseId = $CaseId; DryRun = [bool]$DryRun } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $fakeRunner -Encoding UTF8

    $result = & $scriptPath -CaseId 'CL-AI-010' -DryRun -RunnerPath $fakeRunner | ConvertFrom-Json
    if ($result.stage -ne 'test' -or $result.selector.caseId -ne 'CL-AI-010' -or -not $result.dryRun) {
        throw 'Single-case DryRun was not forwarded correctly.'
    }

    $failed = $false
    try { & $scriptPath -All -Workflow 'subtitle' -DryRun -RunnerPath $fakeRunner | Out-Null }
    catch { $failed = $_.Exception.Message -like '*只能选择一种执行范围*' }
    if (-not $failed) { throw 'Conflicting selectors were not rejected.' }

    Write-Output 'PASS: CinLink test stage selection and DryRun behavior.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```powershell
& ".\tools\tests\run-cinlink-test-stage.Tests.ps1"
```

Expected: failure because `tools/run-cinlink-test-stage.ps1` does not exist.

- [ ] **Step 3: Implement the minimal stage-one wrapper**

Create `tools/run-cinlink-test-stage.ps1` with this public parameter contract:

```powershell
param(
    [switch]$All,
    [ValidateSet('subtitle','translation','enhance','text-watermark','image-watermark','mix','long-to-short')]
    [string]$Workflow,
    [string]$CaseId,
    [switch]$NoRestart,
    [switch]$DryRun,
    [string]$RunnerPath = (Join-Path $PSScriptRoot 'run-cinlink-cases.ps1')
)
```

Implementation requirements:

```powershell
$selectorCount = @([bool]$All, -not [string]::IsNullOrWhiteSpace($Workflow), -not [string]::IsNullOrWhiteSpace($CaseId)).Where({ $_ }).Count
if ($selectorCount -ne 1) { throw '只能选择一种执行范围：-All、-Workflow 或 -CaseId。' }
if (-not (Test-Path -LiteralPath $RunnerPath -PathType Leaf)) { throw "测试执行器不存在：$RunnerPath" }
```

Build a splatted argument map, invoke the runner with `& $RunnerPath @runnerArguments`, preserve a non-zero exit code, discover the newest run directory only for real execution, and emit the final JSON object after the child command output. The wrapper must contain no Yunxiao URL, credential loading, or Git command.

- [ ] **Step 4: Run stage-one tests in both PowerShell runtimes**

Run:

```powershell
& ".\tools\tests\run-cinlink-test-stage.Tests.ps1"
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File ".\tools\tests\run-cinlink-test-stage.Tests.ps1"
```

Expected: both print the PASS line and exit 0.

- [ ] **Step 5: Verify the real catalog without launching CinLink**

Run:

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -Workflow subtitle -DryRun
& ".\tools\run-cinlink-test-stage.ps1" -CaseId CL-AI-010 -DryRun
```

Expected: each emits the selected cases and a final JSON object with `stage: test` and `dryRun: true`; no CinLink process or Yunxiao request is started.

---

### Task 2: Add the Yunxiao Synchronization Stage Entrypoint

**Files:**
- Create: `tools/sync-yunxiao-stage.ps1`
- Create: `tools/tests/sync-yunxiao-stage.Tests.ps1`

**Interfaces:**
- Consumes: `-RunDirectory <path>`, reviewed `<path>/yunxiao-defects.json`, and `tools/sync-yunxiao-defects.ps1`.
- Produces: preview JSON on `-DryRun`; real synchronization only when `-ConfirmWrite` is present, followed by the existing readback result file in the run directory.

- [ ] **Step 1: Write the failing stage-two tests**

Create `tools/tests/sync-yunxiao-stage.Tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\sync-yunxiao-stage.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-yunxiao-stage-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    '{"runId":"fixture","defects":[]}' | Set-Content -LiteralPath (Join-Path $fixtureRoot 'yunxiao-defects.json') -Encoding UTF8
    $fakeSync = Join-Path $fixtureRoot 'sync.ps1'
    @'
param([switch]$DryRun, [string]$ConfigPath, [string]$EvidenceDirectory)
[pscustomobject]@{ dryRun = [bool]$DryRun; configPath = $ConfigPath; evidenceDirectory = $EvidenceDirectory } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $fakeSync -Encoding UTF8

    $preview = & $scriptPath -RunDirectory $fixtureRoot -DryRun -SyncToolPath $fakeSync | ConvertFrom-Json
    if (-not $preview.dryRun -or $preview.configPath -ne (Join-Path $fixtureRoot 'yunxiao-defects.json')) {
        throw 'Preview did not use the reviewed run configuration.'
    }

    $blocked = $false
    try { & $scriptPath -RunDirectory $fixtureRoot -SyncToolPath $fakeSync | Out-Null }
    catch { $blocked = $_.Exception.Message -like '*ConfirmWrite*' }
    if (-not $blocked) { throw 'Real synchronization was not blocked without explicit confirmation.' }

    Write-Output 'PASS: Yunxiao stage preview and write authorization checks.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```powershell
& ".\tools\tests\sync-yunxiao-stage.Tests.ps1"
```

Expected: failure because `tools/sync-yunxiao-stage.ps1` does not exist.

- [ ] **Step 3: Implement the minimal stage-two wrapper**

Create `tools/sync-yunxiao-stage.ps1` with this contract:

```powershell
param(
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [switch]$DryRun,
    [switch]$ConfirmWrite,
    [string]$SyncToolPath = (Join-Path $PSScriptRoot 'sync-yunxiao-defects.ps1')
)
```

Resolve the run directory to an absolute path; require `yunxiao-defects.json`; reject non-DryRun execution unless `-ConfirmWrite` is supplied; then invoke:

```powershell
& $SyncToolPath -ConfigPath $configPath -EvidenceDirectory $resolvedRunDirectory -DryRun:$DryRun
```

On real execution, require `yunxiao-defects-batch-result.json`, parse it, and fail unless `verified -eq requested`. The wrapper must not prompt for a token, because the lower-level tool already uses the DPAPI credential with `-NoPrompt`.

- [ ] **Step 4: Run stage-two tests in both PowerShell runtimes**

Run:

```powershell
& ".\tools\tests\sync-yunxiao-stage.Tests.ps1"
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File ".\tools\tests\sync-yunxiao-stage.Tests.ps1"
```

Expected: both print the PASS line and exit 0.

- [ ] **Step 5: Prepare the existing run for the new contract and preview it**

Copy the reviewed configuration into the run directory as `yunxiao-defects.json` using `apply_patch` or a repository-safe file operation that preserves UTF-8 JSON, then run:

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory ".\output\ui-test\ai-core-smoke-20260820-203313" `
  -DryRun
```

Expected: a 15-item preview with no Yunxiao write. Do not run the real synchronization during implementation unless the user separately authorizes another live write.

---

### Task 3: Create and Link the Repository-Managed Skill

**Files:**
- Create: `skills/cinlink-ai-qa/SKILL.md`
- Create: `skills/cinlink-ai-qa/references/test-stage.md`
- Create: `skills/cinlink-ai-qa/references/yunxiao-stage.md`
- Create: `tools/install-cinlink-ai-qa-skill.ps1`
- Create: `tools/tests/install-cinlink-ai-qa-skill.Tests.ps1`

**Interfaces:**
- Consumes: user intent, repository path, `run-cinlink-test-stage.ps1`, and `sync-yunxiao-stage.ps1`.
- Produces: correct routing to exactly one stage; a directory junction at the requested install destination pointing to `skills/cinlink-ai-qa`.

- [ ] **Step 1: Load the required Skill-authoring guidance**

Read `skill-creator/SKILL.md` and `superpowers:writing-skills/SKILL.md` completely before creating the Skill. Use the repository `skills/cinlink-ai-qa` folder as the single source of truth.

- [ ] **Step 2: Write the failing installer test**

Create `tools/tests/install-cinlink-ai-qa-skill.Tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\install-cinlink-ai-qa-skill.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-skill-install-' + [guid]::NewGuid().ToString('N'))
try {
    $source = Join-Path $fixtureRoot 'source'
    $destination = Join-Path $fixtureRoot 'installed\cinlink-ai-qa'
    $null = New-Item -ItemType Directory -Path $source -Force
    '---`nname: cinlink-ai-qa`ndescription: fixture`n---' | Set-Content -LiteralPath (Join-Path $source 'SKILL.md')

    $plan = & $scriptPath -SourcePath $source -DestinationPath $destination -DryRun | ConvertFrom-Json
    if ($plan.action -ne 'create-junction' -or $plan.destination -ne [IO.Path]::GetFullPath($destination)) {
        throw 'Installer DryRun did not plan the expected junction.'
    }
    if (Test-Path -LiteralPath $destination) { throw 'Installer DryRun changed the filesystem.' }

    Write-Output 'PASS: CinLink Skill installer dry-run behavior.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
```

- [ ] **Step 3: Run the installer test and verify RED**

Run:

```powershell
& ".\tools\tests\install-cinlink-ai-qa-skill.Tests.ps1"
```

Expected: failure because the installer does not exist.

- [ ] **Step 4: Create the Skill instructions and references**

Create `skills/cinlink-ai-qa/SKILL.md` with frontmatter:

```yaml
---
name: cinlink-ai-qa
description: Run CinLink AI workflow tests or synchronize reviewed CinLink test defects to Yunxiao as two independent stages. Use for full, workflow, or single-case CinLink runs and for root-cause-deduplicated Yunxiao evidence updates; never performs Git operations.
---
```

The body must route as follows:

- Test requests read `references/test-stage.md` and invoke only stage one.
- Result-review requests inspect local output without writing Yunxiao.
- Yunxiao requests read `references/yunxiao-stage.md`, run preview first, report create/update/skip counts, and wait for explicit confirmation before real writes.
- Combined requests complete stage one, then pause for human defect review and a separate Yunxiao authorization.
- Git requests explain that commit and push are manual and do not execute them.

Put concrete commands and output expectations in the two references, not duplicated in `SKILL.md`.

- [ ] **Step 5: Implement the idempotent junction installer**

Create `tools/install-cinlink-ai-qa-skill.ps1` with:

```powershell
param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills\cinlink-ai-qa'),
    [string]$DestinationPath = 'C:\Users\chen\.codex\skills\cinlink-ai-qa',
    [switch]$DryRun
)
```

Require `<source>/SKILL.md`. If the destination is absent, plan or create a directory junction with `New-Item -ItemType Junction`. If it is already a junction to the same resolved source, return `unchanged`. If it exists as a normal directory, file, or different junction, stop without deleting or overwriting it. Emit JSON containing `action`, `source`, and `destination`.

- [ ] **Step 6: Run installer tests and Skill validation**

Run:

```powershell
& ".\tools\tests\install-cinlink-ai-qa-skill.Tests.ps1"
python "C:\Users\chen\.codex\skills\.system\skill-creator\scripts\quick_validate.py" ".\skills\cinlink-ai-qa"
```

Expected: installer test PASS and validator reports the Skill is valid.

- [ ] **Step 7: Preview and install the Skill link**

Run:

```powershell
& ".\tools\install-cinlink-ai-qa-skill.ps1" -DryRun
& ".\tools\install-cinlink-ai-qa-skill.ps1"
& ".\tools\install-cinlink-ai-qa-skill.ps1"
```

Expected: first output `create-junction`, second creates the link, third outputs `unchanged`. No existing destination may be removed or overwritten.

---

### Task 4: Document and Verify the Complete Local Workflow

**Files:**
- Modify: `README.md`
- Test: all `tools/tests/*.Tests.ps1`

**Interfaces:**
- Consumes: the two stage commands and the installed `cinlink-ai-qa` Skill.
- Produces: a user-facing workflow that can be followed without reading script internals.

- [ ] **Step 1: Update README with the two-stage workflow**

Add these sections with executable commands:

```markdown
## 阶段一：运行测试

& ".\tools\run-cinlink-test-stage.ps1" -All
& ".\tools\run-cinlink-test-stage.ps1" -Workflow subtitle
& ".\tools\run-cinlink-test-stage.ps1" -CaseId CL-AI-010

## 审核缺陷

审核运行目录中的报告，把确认后的根因写入 `yunxiao-defects.json`。测试失败不会自动写入云效。

## 阶段二：同步云效

& ".\tools\sync-yunxiao-stage.ps1" -RunDirectory "<run-directory>" -DryRun
& ".\tools\sync-yunxiao-stage.ps1" -RunDirectory "<run-directory>" -ConfirmWrite

## GitHub 手动同步

git status --short
git diff --check
git add <reviewed-files>
git commit -m "feat: organize CinLink QA workflow"
git push origin codex/cinlink-ai-smoke-yunxiao
```

State explicitly that users must inspect `git status` and never add `output/` or credential files.

- [ ] **Step 2: Run every PowerShell test script**

Run:

```powershell
$tests = Get-ChildItem ".\tools\tests\*.Tests.ps1" | Sort-Object Name
foreach ($test in $tests) {
    & $test.FullName
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($test.Name)" }
}
```

Expected: every test prints PASS and the command exits 0.

- [ ] **Step 3: Run compatibility and safety checks**

Run:

```powershell
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File ".\tools\tests\run-cinlink-test-stage.Tests.ps1"
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File ".\tools\tests\sync-yunxiao-stage.Tests.ps1"
git diff --check
git status --short
```

Expected: both compatibility tests PASS, `git diff --check` is silent, and Git lists only the intended documentation, scripts, tests, Skill source, and reviewed handoff file.

- [ ] **Step 4: Manually verify the safety boundaries**

Inspect the changed files and confirm:

- `run-cinlink-test-stage.ps1` contains no Yunxiao API URL or credential call.
- `sync-yunxiao-stage.ps1` refuses real writes without `-ConfirmWrite`.
- `SKILL.md` requires preview and explicit authorization before Yunxiao writes.
- No new or modified automation file executes Git mutation commands.
- No token-like literal or DPAPI credential file appears in the diff.

- [ ] **Step 5: Hand off manual Git synchronization**

Report the exact changed-file list, test results, Skill link status, and suggested commit message. Do not run `git add`, `git commit`, `git push`, or create a pull request.
