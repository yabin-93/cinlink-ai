# CinLink AI 测试自动化

本仓库把测试内容分为三层：

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

## 重新运行一条用例

先正常打开 CinLink，再执行：

```powershell
& ".\tools\run-cinlink-cases.ps1" -CaseId "CL-AI-001"
```

脚本会以 CDP 模式重启 CinLink、新建独立的时间戳结果目录、上传素材、输入提示词、保存提交前截图并提交任务。

如果 CinLink 已经通过 `--remote-debugging-port=9222` 启动，可以跳过重启：

```powershell
& ".\tools\run-cinlink-cases.ps1" -CaseId "CL-AI-001" -NoRestart
```

## 串行重新运行全部用例

```powershell
& ".\tools\run-cinlink-cases.ps1" -All
```

每条任务提交后，脚本会暂停。必须等待当前任务结束，完成进度、积分、结果和证据检查，再按 Enter 提交下一条，避免并发任务干扰。

也可以只串行运行某个主流程的 4 条用例：

```powershell
& ".\tools\run-cinlink-cases.ps1" -Workflow "subtitle"
```

可用主流程：`subtitle`、`translation`、`enhance`、`text-watermark`、`image-watermark`、`mix`、`long-to-short`。

## 运行结果

每次运行创建：

```text
output/ui-test/ai-core-smoke-YYYYMMDD-HHMMSS/
```

其中 `run-manifest.json` 记录已提交的用例和截图路径。`submitted` 只表示任务已提交，不代表用例通过；最终结论需要写入该次运行的测试报告。

## 云效缺陷同步

`tools/sync-yunxiao-defects.ps1` 只用于把确认后的缺陷和证据同步到云效，不作为测试用例来源。新增测试用例时不要修改该脚本；只有发现并确认新缺陷后，才扩展缺陷同步数据。
