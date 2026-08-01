<div align="center">

# GrapeCompare

**快速、准确的 macOS 文件与文件夹比较工具。**<br>
原生 SwiftUI，不使用 WebView，灵感来自 Beyond Compare。

[从 App Store 下载](https://apps.apple.com/app/id6796778424) · [English](README.md) · [问题反馈](https://github.com/everettjf/GrapeCompare/issues) · [隐私政策](docs/privacy.html)

</div>

| 文件夹比较 | 文件比较 |
| --- | --- |
| ![文件夹比较](docs/assets/folder-diff.png) | ![文件比较](docs/assets/file-diff.png) |

## 为什么选择 GrapeCompare

- **准确：** 文件夹内容逐字节校验；常规改动生成最短编辑脚本；末尾换行差异清晰可见；正确处理符号链接、package 目录以及文件/文件夹同路径冲突。
- **大规模依然快：** 当前开发机上，10 万行文本端到端比较约 0.06 秒，1 万文件的完整文件夹比较约 0.38 秒。
- **差异清晰：** 左右并排、修改行字符级高亮、对齐行号、差异统计，以及上一处/下一处导航。
- **原生且私密：** 流畅的 macOS 深色/浅色界面，所有处理均在本地完成，仅以只读方式访问用户选择的文件。

## 功能

### 文件比较

- 自适应 Myers 行 diff，大范围重写使用低频公共行锚点分段
- 修改行内的字符级精确高亮
- 新增、删除、修改统计与差异导航
- CRLF/LF 归一化、末尾换行提示与二进制文件检测
- 大文件使用内存映射读取，避免在进入 diff 前复制两份完整内容

### 文件夹比较

- 递归展开树，显示**相同 / 不同 / 仅左侧 / 仅右侧**状态
- 全部/仅差异/仅左侧/仅右侧筛选，包含差异的目录自动展开
- 先检查类型和大小，再以有界并行方式逐字节精确校验
- 正确遍历 package 目录，并按链接目标比较符号链接
- 通过预汇总状态索引快速筛选超大目录树

## 性能

仓库包含使用可重复生成数据的 Release 基准。当前开发机上的代表性结果：

| 场景 | 结果 | 说明 |
| --- | ---: | --- |
| 10 万行、少量编辑 | **0.060 秒** | 端到端：拆行、diff、行内范围、结果建模 |
| 3 万行、高比例改动 | **0.070 秒** | 所有稳定结构锚点均得到保留 |
| 1 万文件目录 | **0.382 秒** | 优化前 2.385 秒，约 **6.2 倍提速** |
| 5 万文件目录 | **3.917 秒** | 完整扫描、校验、建树、排序与汇总 |

数字不包含测试数据生成，实际结果会随硬件和存储设备变化。可在本机复现：

```bash
bash macos/Benchmarks/run-benchmarks.sh
bash macos/Benchmarks/run-benchmarks.sh 100000 50000
```

Diff 设计基于 [Myers O(ND) 算法](https://doi.org/10.1007/BF01840446)，并采纳了 [Git diff 算法文档](https://git-scm.com/docs/diff-algorithm-option.html)中的低频元素锚定思路。

## 安装或构建

可以从 [Mac App Store](https://apps.apple.com/app/id6796778424) 安装已签名版本，也可以使用 macOS 27+ 和 Xcode 27+ 从源码构建：

```bash
xcodebuild -project macos/GrapeCompare.xcodeproj \
  -scheme GrapeCompare \
  -destination 'platform=macOS' \
  -configuration Debug build
```

也可以直接在 Xcode 中打开 `macos/GrapeCompare.xcodeproj` 并运行。

## 命令行

```bash
GrapeCompare <左侧路径> <右侧路径>
```

两个输入都是文件夹时进入文件夹比较，其他情况进入文件比较。App Store 版本启用了沙盒，无法读取任意命令行路径；如需该工作流，请在自行构建时关闭 App Sandbox。

## 测试

```bash
macos/Tests/run-tests.sh
```

核心套件包含 45 项针对性检查、300 组随机最短编辑脚本用例、大文本压力场景和文件夹边界场景，不依赖 UI 或 Xcode 测试运行器。

## 项目结构

```text
macos/
├── GrapeCompare/
│   ├── Core/
│   │   ├── DiffEngine.swift       # 自适应 Myers + 低频锚点
│   │   └── FolderComparator.swift # POSIX 扫描 + 有界并行精确校验
│   ├── Views/                     # 原生 SwiftUI 文件/文件夹界面
│   └── AppState.swift             # 对比任务调度
├── Tests/                         # 确定性正确性与压力测试
└── Benchmarks/                    # 可重复的大文件/文件夹性能基准
```

## 支持

Bug 和功能建议请提交到 [GitHub Issues](https://github.com/everettjf/GrapeCompare/issues)。
