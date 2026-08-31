# Mac App Store metadata — version 1.0.0

Use these reviewed values for the first Mac App Store version. Fields marked
`ACCOUNT REQUIRED` must be completed by the account holder in App Store Connect.

## Shared app information

- Name: `GrapeCompare`
- Bundle ID: `com.xnu.compare`
- SKU: `grapecompare-macos`
- Primary category: `Productivity` (matches `public.app-category.productivity`)
- Secondary category: `Developer Tools`
- Privacy policy URL: `https://xnu.app/grapecompare/privacy.html`
- Support URL: `https://xnu.app/grapecompare/support.html`
- Marketing URL: `https://xnu.app/grapecompare/`
- App privacy answer: `No, we do not collect data from this app`
- Tracking: `No`
- Content rights: the app does not contain, show, or access third-party content
- Encryption: the app does not implement non-exempt encryption;
  `ITSAppUsesNonExemptEncryption` is `false`
- Copyright: `ACCOUNT REQUIRED — use the account holder's legal name`

## English (U.S.)

- Subtitle: `Private File & Folder Diff`
- Keywords: `diff,compare,files,folders,text,image,json,plist,merge,developer`
- Promotional text:

  `Compare files, folders, images, structured data, and three-way merges privately in the macOS App Sandbox.`

- Description:

  ```text
  GrapeCompare is a private, native comparison workspace for macOS. Every comparison runs locally. The app has no account, analytics, advertising, tracking, network entitlement, or cloud upload.

  FILES
  • Compare text line by line and character by character.
  • Navigate differences, search both sides, apply reusable comparison rules, edit an output, and export a unified patch.
  • Compare JSON, property lists, XCStrings, and Xcode project files semantically.

  FOLDERS
  • Scan folders recursively without following symbolic links.
  • Filter identical, changed, left-only, and right-only items.
  • Review safe copy, replace, move, and recoverable delete operations before execution.
  • Use preflight checks, progress, cancellation, transaction history, and validated undo.

  IMAGES AND DEVELOPER FORMATS
  • Inspect images side by side, overlaid, split, blinking, or as a difference heatmap.
  • View metadata and pixel-level difference measurements.
  • Inspect app bundles, code signatures, entitlements, provisioning profiles, Mach-O architectures, and asset catalogs without launching inspected code.

  MERGE
  • Resolve user-selected three-way text and image merges.
  • Choose conflict results individually or in bulk and export the completed result.

  GrapeCompare uses App Sandbox and accesses only files and folders you explicitly select. Finder Open With, drag and drop, recent comparisons, and a macOS 15 or later Shortcut are supported.
  ```

## Simplified Chinese

- Subtitle: `私密文件与文件夹比较`
- Keywords: `文件比较,文件夹比较,文本差异,图片比较,代码比较,合并,JSON,plist`
- Promotional text:

  `在 macOS App Sandbox 中私密比较文件、文件夹、图片、结构化数据并完成三方合并。`

- Description:

  ```text
  GrapeCompare 是一款原生、私密的 macOS 比较工具。全部比较均在本机完成；应用无需账号，不含分析、广告、跟踪、网络权限或云端上传。

  文件比较
  • 文本行级与字符级差异高亮、搜索和差异导航。
  • 可复用比较规则、可编辑输出和统一补丁导出。
  • JSON、属性列表、XCStrings 和 Xcode 项目的语义比较。

  文件夹比较
  • 递归扫描文件夹且不会跟随符号链接。
  • 筛选相同、不同、仅左侧和仅右侧项目。
  • 执行前审查复制、替换、移动和可恢复删除操作。
  • 支持预检、进度、取消、事务历史和经过验证的撤销。

  图片与开发者格式
  • 并排、叠加、分割、闪烁和差异热图模式。
  • 查看元数据和像素级差异指标。
  • 在不启动被检查代码的情况下检查 App Bundle、签名、Entitlements、Provisioning Profile、Mach-O 架构和 Asset Catalog。

  三方合并
  • 对用户主动选择的文本或图片执行三方合并。
  • 逐项或批量解决冲突并导出结果。

  GrapeCompare 启用 App Sandbox，只能访问你明确选择的文件和文件夹。支持 Finder“打开方式”、拖放、最近比较，以及 macOS 15 或更高版本的快捷指令。
  ```

## App Review information

- Sign-in required: `No`
- Demo account: `Not applicable`
- Contact name, phone, and email: `ACCOUNT REQUIRED`
- Review notes:

  ```text
  GrapeCompare is a fully local, sandboxed macOS comparison app. It does not require an account or network connection.

  To review file comparison, choose two text files on the home screen and click Compare. To review folder comparison, choose two folders. File operations are never automatic: select an item, choose a direction, review the preflight sheet, and explicitly confirm execution. Delete operations move items to Trash and can be undone when the output has not changed.

  The Load Demo menu creates local sample data inside the app container and provides deterministic file and folder comparisons without requiring reviewer documents.

  Finder Open With accepts exactly two files or two folders. The Compare Files App Intent is available on macOS 15 or later and also requires exactly two files.

  The app uses no network entitlement, analytics, advertising, tracking, external executables, Git subprocesses, command-line tool, or custom URL scheme. PrivacyInfo.xcprivacy declares no collected data and approved reasons only for app-local UserDefaults and timestamps of user-selected or container files.
  ```

## Age rating and availability

- Select `None` or `Never` for all objectionable-content categories.
- No parental controls, age assurance, unrestricted web access, messaging,
  advertising, gambling, contests, loot boxes, or user-generated online content.
- Pricing, storefront availability, EU trader status, and tax/banking agreements:
  `ACCOUNT REQUIRED`.

## Screenshots

Mac screenshots are required. Upload one to ten opaque PNG or JPEG images at a
single supported 16:10 size. Two upload-ready, opaque 2560×1600 JPEG captures
are checked in under `app-store/screenshots/en-US/`. They are lossless-layout
conversions of the product captures and do not redraw or alter the UI.
