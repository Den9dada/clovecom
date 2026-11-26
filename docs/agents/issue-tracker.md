# Issue 跟踪器：GitHub

本仓库的工单和已发布规格保存在 Den9dada/clovecom 的 GitHub Issues。
本地规格文件可作为草稿，不能代替发布。

## 操作约定

- 优先使用可访问的 GitHub 插件工具；不可用时使用本机已登录的 gh。
- 使用 CLI 时显式指定 --repo Den9dada/clovecom，避免误写上游或其他仓库。
- 创建前核对目标仓库并检索已有工单，避免重复发布。
- 多行正文写入 UTF-8 文件，通过 --body-file 提交。
- 分流标签按 triage-labels.md 的角色映射应用。
- 关闭工单前先发表原因说明，确保已关闭工单也保留说明。
- 子工单和阻塞关系优先使用 GitHub 原生关系；不可用时在正文记录父工单和阻塞工单。
- “发布到 Issue 跟踪器”表示创建 GitHub Issue。
- “获取相关工单”表示读取对应 Issue 的正文、标签和评论。

## PR 分流

PRs as a request surface: no.
