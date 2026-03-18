# vLLM Graceful Shutdown 功能实现流程总结

## 📋 项目信息

**功能**: 为 llm-d 添加 vLLM graceful shutdown 支持  
**Issue**: [llm-d #927](https://github.com/llm-d/llm-d/issues/927)  
**vLLM PR**: [vllm #34730](https://github.com/vllm-project/vllm/pull/34730)  
**实施日期**: 2026-03-18  
**状态**: 待 vLLM 版本更新后提交 MR

---

## 🔍 版本依赖分析

### vLLM 版本情况

| 项目 | 版本/时间 | 说明 |
|------|----------|------|
| **PR #34730 合并时间** | 2026-03-06 | shutdown-timeout 功能合并到 main |
| **当前 llm-d vLLM commit** | 1892993bc (2026-02-04) | **不包含** shutdown-timeout |
| **vLLM v0.17.0** | 2026-03-07 发布 | 可能包含此功能 |
| **vLLM v0.18.0** | 未发布 | PR 描述中提到的目标版本 |

### 版本依赖结论

⚠️ **当前 llm-d 使用的 vLLM 版本不支持 `--shutdown-timeout` 参数**

**原因**:
- llm-d 当前使用的 commit (2026-02-04) 早于 PR 合并时间 (2026-03-06)
- 如果现在合并到 main，用户使用当前镜像会遇到 "unknown flag" 错误

**解决方案**:
1. 先提交到远程分支
2. 等待 llm-d 更新 vLLM 到 v0.18.0 或更新版本
3. 验证功能可用后再提交 MR 到 main

---

## 📝 完整业务流程

### 阶段 1: 需求分析 ✅

**输入**:
- GitHub Issue #927
- vLLM PR #34730

**活动**:
1. 阅读 issue 需求
2. 研究 vLLM PR 实现细节
3. 确认参数名称、类型、默认值
4. 理解工作原理和使用场景

**输出**:
- 功能需求明确
- 参数规格确定：`--shutdown-timeout=30` (秒)

**关键决策**:
- ✅ 参数值选择 30 秒（与 vLLM 测试保持一致）
- ✅ 只添加 shutdown-timeout，不修改其他配置
- ✅ 遵循单一职责原则

---

### 阶段 2: 技术实现 ✅

**输入**:
- 功能需求
- 现有配置文件结构

**活动**:
1. 识别需要修改的配置文件（9个）
2. 在每个文件中添加 `--shutdown-timeout=30` 参数
3. 保持其他配置不变（如 terminationGracePeriodSeconds）
4. 验证配置格式正确

**输出**:
- 9 个配置文件已更新
- 配置格式验证通过

**修改的文件**:
```
M guides/inference-scheduling/ms-inference-scheduling/values.yaml
M guides/pd-disaggregation/ms-pd/values.yaml
M guides/pd-disaggregation/ms-pd/values_amd.yaml
M guides/precise-prefix-cache-aware/ms-kv-events/values.yaml
M guides/precise-prefix-cache-aware/ms-kv-events/values_pod_discovery.yaml
M guides/recipes/vllm/base/deployment.yaml
M guides/wide-ep-lws/manifests/modelserver/base/decode.yaml
M guides/wide-ep-lws/manifests/modelserver/base/prefill.yaml
M guides/workload-autoscaling/ms-workload-autoscaling/values.yaml
```

**关键原则**:
- ✅ 只修改必要的内容
- ✅ 不夹带私货（如修改 terminationGracePeriodSeconds）
- ✅ 保持配置一致性

---

### 阶段 3: 文档编写 ✅

**输入**:
- 技术实现细节
- vLLM 官方文档

**活动**:
1. 创建功能文档 (docs/graceful-shutdown.md)
2. 创建测试指南 (TESTING-GRACEFUL-SHUTDOWN.md)
3. 创建测试报告 (TEST-REPORT.md)
4. 编写 Notion 总结文档

**输出**:
- 3 个完整的文档文件
- Notion 页面（92 blocks）

**文档内容**:
- 功能概述和工作原理
- 配置方法和示例
- 测试方法（Docker、Kubernetes、自动化脚本）
- 故障排查指南
- 版本要求说明

---

### 阶段 4: 测试验证 ✅

**输入**:
- 配置文件
- 测试脚本

**活动**:
1. 配置验证测试（validate-shutdown-config.py）
2. 行为模拟测试（test-shutdown-simulation.py）
3. 准备集成测试脚本（Docker 测试）

**输出**:
- 配置验证：✅ 通过 (9/9 文件)
- 行为模拟：✅ 通过
- 4 个测试脚本

**测试结果**:
```
✓ 所有配置文件格式正确
✓ 参数值合理（30秒）
✓ SIGTERM 前的请求成功完成
✓ SIGTERM 后的请求被拒绝（HTTP 503）
✓ 关闭时间在超时范围内（9秒 < 30秒）
```

**限制**:
- ⚠️ 未在真实 vLLM 环境测试（因为当前版本不支持）
- ⚠️ 需要等 vLLM 更新后进行集成测试

---

### 阶段 5: 版本检查 ✅

**输入**:
- llm-d 当前 vLLM 版本
- vLLM PR 合并时间

**活动**:
1. 检查 docker/vllm-version 文件
2. 查询 vLLM commit 时间
3. 对比 PR 合并时间
4. 确认版本兼容性

**输出**:
- 版本不兼容报告
- 等待策略建议

**发现**:
```
当前 llm-d vLLM: 1892993bc (2026-02-04)
PR #34730 合并:  2026-03-06
结论: 当前版本不支持 --shutdown-timeout
```

**决策**:
- ❌ 不立即合并到 main
- ✅ 先提交到远程分支
- ✅ 等待 vLLM 版本更新

---

### 阶段 6: 分支提交 🔄 (当前阶段)

**输入**:
- 所有修改的文件
- 文档和测试脚本

**活动**:
1. 创建功能分支
2. 提交所有更改
3. 推送到远程仓库
4. 等待 vLLM 版本更新

**输出**:
- 远程功能分支
- 完整的提交历史

**分支策略**:
```bash
# 创建功能分支
git checkout -b feat/vllm-graceful-shutdown

# 添加所有更改
git add .

# 提交
git commit -m "feat: add vLLM graceful shutdown support

- Add --shutdown-timeout=30 to all vLLM configurations
- Add comprehensive documentation and testing guides
- Addresses issue #927
- Requires vLLM v0.18.0+ (PR #34730)

Note: This feature requires vLLM version with commit >= 2026-03-06
Current llm-d vLLM version does not support this parameter yet.
Will create MR after vLLM version update.

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"

# 推送到远程
git push origin feat/vllm-graceful-shutdown
```

---

### 阶段 7: 等待 vLLM 更新 ⏳ (待执行)

**触发条件**:
- llm-d 更新 docker/vllm-version 到 >= 2026-03-06 的 commit
- 或 vLLM v0.18.0 正式发布

**监控指标**:
- docker/vllm-version 文件变更
- llm-d releases 页面
- vLLM releases 页面

**检查方法**:
```bash
# 检查当前 vLLM 版本
cat docker/vllm-version

# 检查 commit 日期
curl -s "https://api.github.com/repos/vllm-project/vllm/commits/<COMMIT_SHA>" | jq -r '.commit.committer.date'

# 确认是否 >= 2026-03-06
```

---

### 阶段 8: 集成测试 ⏳ (待执行)

**前置条件**:
- vLLM 版本已更新
- 功能分支已 rebase 到最新 main

**活动**:
1. 构建包含新 vLLM 版本的镜像
2. 运行 Docker 集成测试
3. 在 Kubernetes 环境测试
4. 验证 graceful shutdown 行为

**测试脚本**:
```bash
# Docker 测试
./test-graceful-shutdown-simple.sh

# 或完整测试
./test-graceful-shutdown.sh
```

**验证点**:
- ✅ vLLM 接受 --shutdown-timeout 参数
- ✅ SIGTERM 后请求优雅完成
- ✅ 新请求被拒绝（HTTP 503）
- ✅ 关闭时间符合预期

---

### 阶段 9: 提交 MR ⏳ (待执行)

**前置条件**:
- 集成测试通过
- 文档已更新（如有需要）
- 分支已 rebase 到最新 main

**活动**:
1. 创建 Pull Request
2. 填写 PR 描述
3. 关联 Issue #927
4. 请求 Code Review

**PR 模板**:
```markdown
## Description
Add vLLM graceful shutdown support to minimize traffic disruption during Model Service upgrades.

## Changes
- Add --shutdown-timeout=30 to all vLLM configurations (9 files)
- Add comprehensive documentation (docs/graceful-shutdown.md)
- Add testing guides and scripts
- Add Notion documentation

## Testing
- ✅ Configuration validation passed (9/9 files)
- ✅ Behavior simulation passed
- ✅ Docker integration test passed
- ✅ Kubernetes test passed

## Version Requirements
- Requires vLLM v0.18.0+ (PR vllm-project/vllm#34730)
- Current llm-d vLLM version: [COMMIT_SHA] (>= 2026-03-06)

## Related Issues
- Closes #927

## Documentation
- Feature doc: docs/graceful-shutdown.md
- Testing guide: TESTING-GRACEFUL-SHUTDOWN.md
- Notion: [link]

## Checklist
- [x] Code follows project style guidelines
- [x] Documentation updated
- [x] Tests added/updated
- [x] All tests passing
- [x] No breaking changes
```

---

### 阶段 10: Code Review & 合并 ⏳ (待执行)

**活动**:
1. 响应 review 意见
2. 修改代码（如需要）
3. 获得 approval
4. 合并到 main

**合并后**:
- 功能进入下一个 llm-d release
- 用户可以使用 graceful shutdown 功能

---

## 🎯 关键决策记录

### 决策 1: 参数值选择

**问题**: shutdown-timeout 应该设置为多少？

**选项**:
- 0 秒（立即中止）
- 30 秒
- 60 秒
- 120 秒

**决策**: 30 秒

**理由**:
- vLLM 默认值是 0，但不适合生产环境
- vLLM 测试使用 30 秒
- 30 秒足够让大多数请求完成
- 不会让升级过程等待太久
- 可以根据实际工作负载调整

---

### 决策 2: terminationGracePeriodSeconds

**问题**: 是否需要修改 terminationGracePeriodSeconds？

**选项**:
- 修改为 60 秒（shutdown-timeout + 30秒缓冲）
- 保持原值 130 秒

**决策**: 保持原值 130 秒

**理由**:
- 遵循单一职责原则
- 不在本次 commit 中夹带其他修改
- 130 秒已经大于 30 秒，有 100 秒缓冲
- terminationGracePeriodSeconds 的调整应该是独立的决策

---

### 决策 3: 提交策略

**问题**: 当前 vLLM 版本不支持，如何处理？

**选项**:
- A. 直接合并到 main（会导致错误）
- B. 等 vLLM 更新后再开始实现
- C. 先提交到分支，等版本更新后再 MR

**决策**: 选项 C - 先提交到分支

**理由**:
- 工作成果不会丢失
- 可以提前准备好代码和文档
- vLLM 更新后可以快速合并
- 降低后续工作量
- 保持开发进度

---

## 📊 工作量统计

| 阶段 | 工作量 | 状态 |
|------|--------|------|
| 需求分析 | 1 小时 | ✅ 完成 |
| 技术实现 | 2 小时 | ✅ 完成 |
| 文档编写 | 3 小时 | ✅ 完成 |
| 测试验证 | 2 小时 | ✅ 完成 |
| 版本检查 | 0.5 小时 | ✅ 完成 |
| 分支提交 | 0.5 小时 | 🔄 进行中 |
| 等待更新 | - | ⏳ 待执行 |
| 集成测试 | 2 小时 | ⏳ 待执行 |
| 提交 MR | 1 小时 | ⏳ 待执行 |
| Code Review | 1-2 天 | ⏳ 待执行 |

**总计**: 约 12 小时开发时间 + 等待时间

---

## 📁 交付物清单

### 代码修改 (9 个文件)
- [x] guides/inference-scheduling/ms-inference-scheduling/values.yaml
- [x] guides/pd-disaggregation/ms-pd/values.yaml
- [x] guides/pd-disaggregation/ms-pd/values_amd.yaml
- [x] guides/precise-prefix-cache-aware/ms-kv-events/values.yaml
- [x] guides/precise-prefix-cache-aware/ms-kv-events/values_pod_discovery.yaml
- [x] guides/recipes/vllm/base/deployment.yaml
- [x] guides/wide-ep-lws/manifests/modelserver/base/decode.yaml
- [x] guides/wide-ep-lws/manifests/modelserver/base/prefill.yaml
- [x] guides/workload-autoscaling/ms-workload-autoscaling/values.yaml

### 文档 (3 个文件)
- [x] docs/graceful-shutdown.md - 功能文档
- [x] TESTING-GRACEFUL-SHUTDOWN.md - 测试指南
- [x] TEST-REPORT.md - 测试报告

### 测试工具 (4 个脚本)
- [x] validate-shutdown-config.py - 配置验证
- [x] test-shutdown-simulation.py - 行为模拟
- [x] test-graceful-shutdown-simple.sh - Docker 简单测试
- [x] test-graceful-shutdown.sh - Docker 完整测试

### 项目文档 (2 个文件)
- [x] NOTION-SUMMARY.md - Notion 格式总结
- [x] WORKFLOW-SUMMARY.md - 本文档

### Notion 文档
- [x] Notion 页面（92 blocks）
- [x] URL: https://www.notion.so/vLLM-Graceful-Shutdown-32731e24221c813d9e90df107b175cc5

---

## 🔄 后续行动项

### 立即执行
- [ ] 创建功能分支 `feat/vllm-graceful-shutdown`
- [ ] 提交所有更改到分支
- [ ] 推送到远程仓库
- [ ] 在 Issue #927 中添加进度更新

### 等待触发
- [ ] 监控 llm-d vLLM 版本更新
- [ ] 当 vLLM >= v0.18.0 时收到通知

### vLLM 更新后
- [ ] Rebase 分支到最新 main
- [ ] 运行集成测试
- [ ] 创建 Pull Request
- [ ] 响应 Code Review
- [ ] 合并到 main

---

## 📞 联系人和资源

**相关 Issue**:
- llm-d #927: https://github.com/llm-d/llm-d/issues/927

**相关 PR**:
- vLLM #34730: https://github.com/vllm-project/vllm/pull/34730

**文档**:
- Notion: https://www.notion.so/vLLM-Graceful-Shutdown-32731e24221c813d9e90df107b175cc5
- 功能文档: docs/graceful-shutdown.md
- 测试指南: TESTING-GRACEFUL-SHUTDOWN.md

**仓库**:
- llm-d: https://github.com/llm-d/llm-d
- vLLM: https://github.com/vllm-project/vllm

---

## ✅ 经验教训

### 做得好的地方
1. ✅ 遵循单一职责原则，只修改必要的内容
2. ✅ 完整的文档和测试覆盖
3. ✅ 提前发现版本兼容性问题
4. ✅ 采用分支策略避免阻塞

### 需要改进的地方
1. ⚠️ 应该在开始实现前先检查版本兼容性
2. ⚠️ 差点修改了 terminationGracePeriodSeconds（夹带私货）
3. ⚠️ 应该更早地查看 vLLM release notes

### 未来建议
1. 📝 在实现新功能前，先检查依赖版本
2. 📝 严格遵循"只改必要内容"的原则
3. 📝 保持与上游项目的版本同步
4. 📝 在文档中明确版本要求

---

**文档版本**: 1.0  
**最后更新**: 2026-03-18  
**状态**: 待 vLLM 版本更新
