# GrapeCompare

GrapeCompare 是一款面向 macOS 的私密沙盒比较工具，支持文件、文件夹、图片、
结构化数据和三方合并。所有处理均在本机完成；应用没有账号、遥测、网络权限或
云端上传。

## 产品范围

- 文本行级与字符级比较、导航、过滤、可编辑输出和统一补丁导出。
- 文件夹递归比较，以及经过预览确认的事务式复制、替换、移动、可恢复删除、
  Dry Run 报告和撤销。
- 图片并排、叠加、热图、对齐、元数据和像素指标比较。
- JSON、plist、XCStrings 和 Xcode 项目的语义比较。
- 在不启动被检查代码的前提下检查 App Bundle、签名、Entitlements、
  Provisioning Profile、Mach-O 和 Asset Catalog。
- 用户手动选择输入的文本与图片三方合并。
- Finder“打开方式”、拖放、最近比较，以及 macOS 15+ 快捷指令。

GrapeCompare 明确不包含 CLI、Git 子进程集成、difftool/mergetool、任意路径
URL Scheme 或非沙盒发行版本。

## 要求与构建

需要 macOS 14 或更高版本。使用 Xcode 打开 `macos/GrapeCompare.xcodeproj`，
选择 `GrapeCompare` Scheme 并为“我的 Mac”构建。Debug 和 Release 都启用
App Sandbox、用户所选文件读写权限和应用级安全书签。

```bash
bash macos/Tests/run-tests.sh
ruby macos/Tests/validate-localizations.rb
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```

## 发布

唯一支持的产品发行渠道是 Mac App Store。使用 Apple Distribution 签名和
Mac App Store Provisioning Profile，通过 Xcode Archive 上传。任何构建都不得
关闭 App Sandbox。
