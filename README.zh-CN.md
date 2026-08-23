<div align="center">
  <img src="macos/GrapeCompare/Assets.xcassets/GrapeIcon.imageset/grape-icon.png" width="112" alt="GrapeCompare 应用图标">

# GrapeCompare

**快速、准确的 macOS 文件与文件夹比较工具。**<br>
原生 SwiftUI，灵感来自 Beyond Compare——不使用 WebView，不上传云端。

[![最新版本](https://img.shields.io/github/v/release/everettjf/GrapeCompare?display_name=tag&sort=semver&style=flat-square&color=7c3aed)](https://github.com/everettjf/GrapeCompare/releases/latest)
[![自动测试](https://img.shields.io/github/actions/workflow/status/everettjf/GrapeCompare/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/everettjf/GrapeCompare/actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)

[Homebrew](#安装) · [官网](https://xnu.app/grapecompare/) · [English](README.md) · [更新记录](CHANGELOG.md) · [参与贡献](CONTRIBUTING.md)

</div>

## 每一处差异都清晰可见

### 文件夹比较

在可筛选的递归目录树中查看结果，并从不同的文件直接进入文本对比。

<p align="center">
  <img src="docs/assets/folder-diff.png" width="100%" alt="GrapeCompare 文件夹比较界面，展示递归结果树和状态筛选">
</p>

### 文件比较

左右对齐查看行差异、字符级修改、差异统计，以及上一处/下一处导航。

<p align="center">
  <img src="docs/assets/file-diff.png" width="100%" alt="GrapeCompare 左右并排文件比较界面和行内高亮">
</p>

## 为什么选择 GrapeCompare

- **准确：** 文件夹内容逐字节校验；常规改动生成最短编辑脚本；末尾换行差异清晰可见；正确处理符号链接、package 目录以及文件/文件夹同路径冲突。
- **大规模依然快：** 当前开发机上，10 万行文本端到端比较约 0.06 秒，1 万文件的完整文件夹比较约 0.38 秒。
- **差异清晰：** 左右并排、修改行字符级高亮、对齐行号、差异统计，以及上一处/下一处导航。
- **原生且私密：** 流畅的 macOS 深色/浅色界面，所有处理均在本地完成；沙盒读写权限仅限您明确选择的文件夹。

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
- 支持逐项和多选批量规划**左 → 右 / 右 → 左**操作
- 执行前预检真实项目数与字节数，并显示覆盖警告、进度、取消和逐项结果
- 支持安全复制、备份后覆盖、目标不存在时移动，以及可恢复的**移入废纸篓**
- 持久保存撤销历史并保护已被用户修改的输出，重启 App 后仍可安全撤销；跨卷移动会先复制并逐字节验证，再将源项目移入废纸篓
- 执行前明确选择“首次失败即停止”或“失败后继续”，执行中显示速度与预计剩余时间
- 支持导入/导出安全的 `.grapeplan` 方案，将经过校验的相对路径操作映射到当前文件夹对

完整的约定与验收条件见 [v1.3 安全文件操作方案](docs/v1.3-safe-operations.md)和 [v1.4 持久工作流方案](docs/v1.4-durable-workflows.md)。

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

## 安装

通过 Homebrew 安装经过签名和 Apple notarization 的直接分发版本：

```bash
brew install --cask everettjf/tap/grapecompare
```

GrapeCompare 支持 macOS 15 及更高版本。从源码构建需要 Xcode 26 或更高版本：

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

两个输入都是文件夹时进入文件夹比较，其他情况进入文件比较。Homebrew 版本不受 App Store 沙盒限制，可以直接读取 Git 等工具传入的任意临时路径。

## 开发

无需打开 Xcode 即可运行平台无关的核心测试：

```bash
bash macos/Tests/run-tests.sh
```

测试套件包含针对比较与事务的专项检查、300 组随机最短编辑脚本用例、大文本压力场景和文件系统安全场景；Pull Request 会在 GitHub Actions 中运行同一套测试。

```text
macos/
├── GrapeCompare/
│   ├── Core/
│   │   ├── DiffEngine.swift       # 自适应 Myers + 低频锚点
│   │   ├── FolderComparator.swift # POSIX 扫描 + 有界并行精确校验
│   │   └── FileOperations.swift   # 预检、事务、验证与撤销
│   ├── Views/                     # 原生 SwiftUI 文件/文件夹界面
│   └── AppState.swift             # 对比任务调度
├── Tests/                         # 确定性正确性与压力测试
└── Benchmarks/                    # 可重复的大文件/文件夹性能基准
```

欢迎参与贡献。提交 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。问题与建议请使用 [GitHub Issues](https://github.com/everettjf/GrapeCompare/issues)；安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。参与本项目即表示同意遵守 [行为准则](CODE_OF_CONDUCT.md)。
