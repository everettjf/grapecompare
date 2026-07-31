# GrapeCompare

[English README](README.md)

一个受 Beyond Compare 启发的原生 macOS 文件与文件夹比较工具——纯 SwiftUI 开发，不使用 WebView。

## 功能

### 文件夹比较
- 递归比较两个文件夹，以可展开的树形结构展示结果
- 条目状态：**相同 / 不同 / 仅左侧 / 仅右侧**，文件夹状态由后代自动汇总
- 支持筛选（全部 / 仅差异 / 仅左侧 / 仅右侧）、大小列与底部统计栏
- 包含差异的文件夹自动展开；双击文件直接查看其 diff
- 文件先比大小，再按 1MB 分块流式比对内容，大文件不占内存

### 文件比较
- 左右并排 diff，行级红/绿高亮，修改行带**行内字符级精确高亮**
- 行号、对齐空行、二进制文件检测、"文件完全相同"状态
- 差异统计（`+新增 −删除 ~修改`）与上一处/下一处差异导航
- Myers O(ND) 行 diff，带公共前后缀裁剪与编辑距离兜底，大文件少量改动毫秒级完成（10 万行约 0.05 秒）

### 通用
- 深色/浅色模式均有精致观感，支持拖放或点选输入
- 支持命令行调用，类似 `bcompare`：

  ```bash
  GrapeCompare <左> <右>   # 两个目录走文件夹比较，否则走文件比较
  ```

## 环境要求

- macOS 27+，Xcode 27+

## 构建与运行

用 Xcode 打开 `macos/GrapeCompare.xcodeproj` 直接运行，或：

```bash
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
    -destination 'platform=macOS' -configuration Debug build
```

## 测试

与 UI 无关的核心引擎（`DiffEngine`、`FolderComparator`）配有独立测试：

```bash
macos/Tests/run-tests.sh   # 用 swiftc 编译并运行 29 项断言
```

## 项目结构

```
macos/
├── GrapeCompare/
│   ├── GrapeCompareApp.swift      # @main 入口
│   ├── AppState.swift             # 应用状态、比较调度、命令行参数
│   ├── Core/
│   │   ├── DiffEngine.swift       # Myers 行 diff + 对齐行 + 行内差异区间
│   │   └── FolderComparator.swift # 递归文件夹扫描 + 流式文件比对
│   └── Views/
│       ├── HomeView.swift         # 首页：模式选择 + 拖放槽位
│       ├── FileDiffView.swift     # 并排 diff 视图
│       ├── FolderCompareView.swift# 文件夹树视图
│       └── Theme.swift            # 统一配色与字体
└── Tests/
    ├── main.swift                 # 核心测试
    └── run-tests.sh
```

## 说明

- 为让命令行可读取任意路径，App Sandbox 已关闭（与 Beyond Compare 取舍一致）。如计划上架 App Store，请重新开启沙盒。
