# CinLink AI 测试自动化

本仓库把工作分为两个独立阶段：先执行测试并保存本地证据，人工审核后再单独同步云效。测试失败不会自动创建缺陷，GitHub 始终手动同步。

内容分为三层：

- `test-cases/`：可复用的测试用例数据，包括提示词、素材、人工动作和预期结果。
- `tools/`：操作 CinLink、保存证据和同步云效的执行工具。
- `output/`：每次运行产生的截图、清单、报告和诊断文件。该目录被 Git 忽略。

## 新增或修改用例

编辑 `test-cases/cinlink-ai-core.json`，在 `cases` 数组中新增对象。`id` 必须唯一；`files` 使用绝对路径；需要取消、确认方案等操作时写入 `manualActions`。

先检查用例和执行计划，不操作 CinLink：

```powershell
& ".\tools\run-cinlink-cases.ps1" -CaseId "CL-AI-001" -DryRun
& ".\tools\run-cinlink-cases.ps1" -All -DryRun
```

按主流程查看该流程的 4 条用例：

```powershell
& ".\tools\run-cinlink-cases.ps1" -Workflow "subtitle" -DryRun
```

## 安装自然语言 Skill

仓库中的 `skills/cinlink-ai-qa/` 是 Skill 的唯一维护源。首次使用时建立到 Codex Skill 目录的链接：

```powershell
& ".\tools\install-cinlink-ai-qa-skill.ps1" -DryRun
& ".\tools\install-cinlink-ai-qa-skill.ps1"
```

安装后可以直接提出：

- “执行 CinLink 全部测试”
- “只执行字幕流程”
- “重新执行 CL-AI-010”
- “检查这次测试结果”
- “同步这次缺陷到云效”

Skill 会把测试和云效同步保持为两个独立阶段，也不会执行 Git 操作。

## 阶段一：运行测试

统一入口为 `tools/run-cinlink-test-stage.ps1`：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -All
& ".\tools\run-cinlink-test-stage.ps1" -Workflow "subtitle"
& ".\tools\run-cinlink-test-stage.ps1" -CaseId "CL-AI-010"
```

先检查执行范围和提示词、不操作 CinLink：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -All -DryRun
```

### 重新运行一条用例

先正常打开 CinLink，再执行：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -CaseId "CL-AI-001"
```

脚本会以 CDP 模式重启 CinLink、新建独立的时间戳结果目录、上传素材、输入提示词、保存提交前截图并提交任务。

如果 CinLink 已经通过 `--remote-debugging-port=9222` 启动，可以跳过重启：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -CaseId "CL-AI-001" -NoRestart
```

### 串行重新运行全部用例

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -All
```

每条任务提交后，脚本会暂停。必须等待当前任务结束，完成进度、积分、结果和证据检查，再按 Enter 提交下一条，避免并发任务干扰。

也可以只串行运行某个主流程的 4 条用例：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -Workflow "subtitle"
```

可用主流程：`subtitle`、`translation`、`enhance`、`text-watermark`、`image-watermark`、`mix`、`long-to-short`。

## 运行结果

每次运行创建：

```text
output/ui-test/ai-core-smoke-YYYYMMDD-HHMMSS/
```

其中 `run-manifest.json` 记录已提交的用例和截图路径。`submitted` 只表示任务已提交，不代表用例通过；最终结论需要写入该次运行的测试报告。

## 审核缺陷

审核运行目录中的 `smoke-test-report.md`、`execution-observations.json`、截图和诊断附件。将确认后的产品缺陷按根因合并，写入同一运行目录下的 `yunxiao-defects.json`。

运行器自身问题不要写成 CinLink 产品缺陷。没有 `yunxiao-defects.json` 时，云效阶段会拒绝执行。

## 阶段二：同步云效

先预检，不写云效：

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory ".\output\ui-test\ai-core-smoke-20260820-203313" `
  -DryRun
```

检查运行 ID、缺陷数、标题、Job ID 和证据路径。明确确认后才执行真实写入：

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory ".\output\ui-test\ai-core-smoke-20260820-203313" `
  -ConfirmWrite
```

同步器先查询云效现有缺陷，按标题和同根因别名去重；命中时追加回归证据，未命中才新建。重复运行同一批次会跳过已有同步标记和附件。

`tools/sync-yunxiao-defects.ps1` 是底层 API 工具，不作为测试用例来源。日常操作应使用阶段二入口。

## GitHub 手动同步

自动化不会执行 Git 写操作。完成测试后由你检查并手动同步：

```powershell
git status --short
git diff --check
git add README.md docs skills test-cases tools
git commit -m "feat: organize CinLink QA workflow"
git push origin codex/cinlink-ai-smoke-yunxiao
```

执行 `git add` 前必须查看 `git status`。不要提交 `output/`、令牌、DPAPI 凭据或其他本地秘密文件。
