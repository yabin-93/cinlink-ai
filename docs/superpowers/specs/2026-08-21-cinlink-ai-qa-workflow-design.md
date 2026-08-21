# CinLink AI 测试与云效同步分阶段工作流设计

## 目标

把现有 CinLink AI 测试自动化整理为两个彼此独立、可重复执行的阶段：

1. 执行 CinLink 测试并生成本地证据。
2. 审核测试结果后，将确认的缺陷同步到云效。

GitHub 提交和推送始终由陈亚宾手动完成，不属于自动化阶段，也不由 Skill 触发。

## 推荐方案

创建一个 `cinlink-ai-qa` Skill 作为自然语言入口，保留 PowerShell 脚本作为确定性执行层。Skill 只负责识别用户想执行的阶段、检查输入和调用对应脚本，不把测试、云效写入与 Git 操作合并为一个不可拆分流程。

该结构兼顾易用性和可维护性：日常可以直接说“执行全部测试”或“同步这次缺陷到云效”，排错时仍可直接运行独立脚本。

## 目录结构

```text
test/
├── test-cases/
│   ├── cinlink-ai-core.json
│   └── yunxiao-*.json
├── tools/
│   ├── run-cinlink-test-stage.ps1
│   ├── sync-yunxiao-stage.ps1
│   ├── run-cinlink-cases.ps1
│   ├── sync-yunxiao-defects.ps1
│   └── tests/
├── output/ui-test/<run-id>/
│   ├── run-manifest.json
│   ├── execution-observations.json
│   ├── smoke-test-report.md
│   ├── yunxiao-defects.json
│   └── screenshots-and-attachments
└── skills/cinlink-ai-qa/
    ├── SKILL.md
    └── references/
        ├── test-stage.md
        └── yunxiao-stage.md
```

仓库内的 `skills/cinlink-ai-qa/` 是可版本管理的 Skill 源文件。需要在 Codex 中启用时，再通过安装或链接方式部署到用户 Skill 目录。仓库代码和用户环境中的已安装副本不得成为两个独立维护源。

## 阶段一：执行测试

### 输入

- 用例集，默认 `test-cases/cinlink-ai-core.json`。
- 执行范围：全部用例、指定工作流或指定用例 ID。
- CinLink 当前登录账号和项目。
- 用例中声明的视频、图片及其他素材。

### 入口

`tools/run-cinlink-test-stage.ps1` 作为稳定入口，封装现有 `run-cinlink-cases.ps1`：

```powershell
& ".\tools\run-cinlink-test-stage.ps1" -All
& ".\tools\run-cinlink-test-stage.ps1" -Workflow "subtitle"
& ".\tools\run-cinlink-test-stage.ps1" -CaseId "CL-AI-010"
```

入口脚本负责参数校验、创建或复用运行目录、调用现有执行器，并输出本轮运行目录的绝对路径。底层 CDP、素材上传和任务提交能力仍保留在现有脚本中，避免重复实现。

### 输出契约

每次执行使用独立的 `<run-id>` 目录，至少包含：

- `run-manifest.json`：计划和已提交用例、提示词、素材、Job ID 与证据路径。
- `execution-observations.json`：逐用例最终状态和机器可读结论。
- `smoke-test-report.md`：面向人工审核的报告。
- 截图、诊断包、抽帧和下载产物。

阶段一不得创建或更新云效工作项。测试任务完成不等于缺陷已经确认。

## 人工审核边界

测试完成后先由用户或测试人员审核报告，将同一根因的多个失败用例合并，再生成该运行目录下的 `yunxiao-defects.json`。

该文件是阶段一与阶段二之间唯一的业务交接文件，记录：

- 稳定缺陷键和严重级别。
- 标题及同根因历史标题别名。
- 测试步骤、提示词、Job ID、实际结果和预期结果。
- 证据文件名。
- 本次运行的稳定同步标记。

没有经过审核的失败用例不得自动转换为云效缺陷。测试运行器自身问题也不得混入 CinLink 产品缺陷。

## 阶段二：同步云效

### 输入

- 明确指定的运行目录，或用户确认采用的最近一次完整运行目录。
- 该目录中的 `yunxiao-defects.json`。
- 已配置的云效 DPAPI 凭据。

### 入口

`tools/sync-yunxiao-stage.ps1` 作为稳定入口，封装现有 `sync-yunxiao-defects.ps1`：

```powershell
& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory ".\output\ui-test\ai-core-smoke-20260820-203313" `
  -DryRun

& ".\tools\sync-yunxiao-stage.ps1" `
  -RunDirectory ".\output\ui-test\ai-core-smoke-20260820-203313"
```

默认先执行 `-DryRun` 预检。真实写入属于外部变更，Skill 必须展示预计的新建、更新和跳过数量，并在用户明确确认后再执行非 DryRun 命令。

### 去重与幂等规则

同步以“根因”而不是单个失败用例去重：

1. 查询目标项目现有缺陷。
2. 用精确标题和配置中的历史标题别名匹配同根因缺陷。
3. 命中一条时追加本轮回归记录和缺失证据，不新建。
4. 未命中时创建新缺陷。
5. 命中多条时停止，不自动选择目标。
6. 描述中使用 `<run-id> + defect key` 组成稳定同步标记。
7. 已有标记和同名附件再次出现时直接跳过。

同步完成后必须回读验证标题、负责人、优先级、严重程度、Job ID、描述中的图片永久链接和附件列表，并在运行目录保存结果 JSON。

## Skill 行为

`cinlink-ai-qa` Skill 支持以下意图：

- “执行 CinLink 全部测试”：只运行阶段一。
- “只执行字幕流程”：以工作流过滤运行阶段一。
- “重新执行 CL-AI-010”：以用例 ID 运行阶段一。
- “检查这次测试结果”：读取报告和证据，不写云效。
- “同步这次缺陷到云效”：先预检阶段二，获得确认后写入。
- “执行测试并同步云效”：先执行阶段一；完成后暂停，等待人工审核和独立同步授权，不自动连续写入。

Skill 不执行 `git add`、`git commit`、`git push` 或创建 GitHub PR。最多在用户询问时给出手动命令和待提交文件清单。

## 错误与恢复

- 阶段一失败时保留运行目录和已有证据，可按用例 ID 重新执行，不触发云效同步。
- 报告或 `yunxiao-defects.json` 缺失时，阶段二停止并说明缺失文件。
- 云效查询失败时不得退化为直接创建，避免重复缺陷。
- 某条附件上传或回读失败时保存批次状态；重新运行时从已有工作项和附件继续。
- 同一运行目录重复同步必须得到“新建 0、更新 0、幂等跳过 N”的稳定结果。
- 凭据只从环境变量或 DPAPI 缓存读取，不写入仓库、报告、日志或命令输出。

## 测试策略

### 阶段一

- 参数互斥和必填校验。
- 全部、工作流、单用例三种选择方式。
- DryRun 不启动 CinLink、不提交任务。
- 运行目录及清单文件生成。
- 子执行器失败时保留退出码和现场。

### 阶段二

- 运行目录和交接文件校验。
- DryRun 不调用云效写接口。
- 精确标题、别名和多重命中行为。
- 新建、更新、附件跳过和同步标记幂等性。
- 回读不一致时失败并保存错误记录。
- Windows PowerShell 5.1 与当前 PowerShell 兼容性。

### Skill

- 用真实示例验证自然语言能正确路由到阶段一或阶段二。
- 验证“跑测试”不会触发云效 API。
- 验证“同步云效”先预检并等待授权。
- 验证所有 Git 操作均保持手动。

## 验收标准

- 测试执行和云效同步具有两个独立命令入口，可分别运行。
- 阶段一不会因为测试失败而自动创建缺陷。
- 阶段二只读取指定运行目录的已审核交接文件。
- 同根因失败被合并，重复运行不产生重复缺陷或附件。
- Skill 能按自然语言选择正确阶段，并在云效写入前暂停确认。
- GitHub 全流程保持手动，没有脚本或 Skill 自动提交和推送。
- 现有单用例、按工作流和全部用例的运行能力保持兼容。
