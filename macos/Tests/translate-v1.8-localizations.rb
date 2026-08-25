#!/usr/bin/env ruby
require "rexml/document"

translations = {
  "%lld added" => "新增 %lld 行", "%lld modified" => "修改 %lld 行", "%lld removed" => "移除 %lld 行",
  "%lld selected" => "已选择 %lld 项", "Actions for %lld selected items" => "对 %lld 个已选项目执行操作",
  "Choose a focused workflow or drop two items for a quick comparison" => "选择一种工作流，或拖入两个项目快速比较",
  "Clear Recent Comparisons" => "清除最近比较", "Clear Selection" => "清除选择",
  "Code size: %.0f pt" => "代码字号：%.0f 磅", "Comfortable diff row spacing" => "使用舒适的差异行间距",
  "Compare Metadata" => "比较元数据", "Comparison and ignore options" => "比较和忽略选项",
  "Continue Comparing" => "继续比较", "Copy Path" => "复制路径", "Copy →" => "复制 →",
  "Current difference" => "当前差异", "Home" => "首页", "Hunk %1$lld of %2$lld" => "差异块 %1$lld，共 %2$lld",
  "More" => "更多", "More Workflows" => "更多工作流", "More operations for the selected rows" => "对已选行执行更多操作",
  "New Comparison (⌘N)" => "新建比较 (⌘N)", "Options" => "选项", "Please choose a folder." => "请选择文件夹。",
  "Queue operations, synchronize folders, or manage plans" => "将操作加入队列、同步文件夹或管理计划",
  "Quick compare, resolve a merge, or inspect a Git repository" => "快速比较、解决合并冲突或检查 Git 仓库",
  "Recent comparison actions" => "最近比较操作", "Reopen inputs and compare their current contents" => "重新打开输入项目并比较其当前内容",
  "Resume Last" => "恢复上次比较", "Selected Items" => "已选项目", "Show Load Demo button" => "显示“载入演示”按钮",
  "Start a Comparison" => "开始比较", "Synchronization" => "同步", "← Copy" => "← 复制",
  "%@" => "%@", "%1$lld / %2$lld pixels" => "%1$lld / %2$lld 像素",
  "%lld changes" => "%lld 项更改", "%lld conflicts" => "%lld 个冲突",
  "%lld structured differences" => "%lld 项结构化差异",
  "A writable right-side file is required." => "需要可写的右侧文件。",
  "Added" => "已添加", "Base" => "基准", "Base lines %@" => "基准第 %@ 行",
  "Both" => "两者", "Change" => "更改", "Choose exactly two files to compare." => "请选择恰好两个文件进行比较。",
  "Choose exactly two local files." => "请选择恰好两个本地文件。", "Compare ${files}" => "比较 ${files}",
  "Compare Git Repository" => "比较 Git 仓库", "Compare base, ours, and theirs; resolve conflicts into editable output" => "比较基准、我方和对方版本，并将冲突解决到可编辑输出中",
  "Compare branches, commits, index, and working tree without checkout" => "无需检出即可比较分支、提交、索引和工作区",
  "Conflicts" => "冲突", "Copied" => "已复制", "Deleted" => "已删除", "Difference Heatmap" => "差异热图",
  "Discard Changes" => "放弃更改", "Discard merge output?" => "放弃合并输出？", "Editable Merge Output" => "可编辑的合并输出",
  "Editable Output" => "可编辑输出", "Editable comparison output" => "可编辑的比较输出", "Editable three-way merge output" => "可编辑的三方合并输出",
  "Exact whitespace" => "精确空白", "Export Failed" => "导出失败", "Export Result…" => "导出结果…",
  "Export the merge result before leaving if you want to keep it." => "若要保留合并结果，请在离开前导出。",
  "File" => "文件", "Files" => "文件", "Filter paths" => "筛选路径", "Filter paths or values" => "筛选路径或值",
  "From revision" => "起始版本", "Git Comparison Failed" => "Git 比较失败", "Go to line" => "跳转到行",
  "Hide output" => "隐藏输出", "Hunk %1$lld/%2$lld" => "差异块 %1$lld/%2$lld", "Ignore all whitespace" => "忽略所有空白",
  "Ignore case" => "忽略大小写", "Ignore final newline" => "忽略末尾换行", "Ignore line-ending format" => "忽略行尾格式",
  "Ignore whitespace changes" => "忽略空白变化", "Image difference heatmap" => "图片差异热图", "Image display" => "图片显示",
  "Images are identical" => "图片完全相同", "Images differ" => "图片存在差异",
  "Independent and identical changes were merged automatically." => "独立更改和相同更改已自动合并。",
  "Left image" => "左侧图片", "Left: %1$lld×%2$lld" => "左侧：%1$lld×%2$lld", "Line" => "行",
  "Maximum channel difference: %u" => "最大通道差异：%u", "Merge" => "合并", "Merge Failed" => "合并失败",
  "Merging…" => "正在合并…", "Modified" => "已修改", "Next hunk" => "下一个差异块", "Next search result" => "下一个搜索结果",
  "No Conflicts" => "没有冲突", "No Git Differences" => "没有 Git 差异",
  "Object key order and serialization format are ignored." => "对象键顺序和序列化格式将被忽略。",
  "Open Repository" => "打开仓库", "Open two files in GrapeCompare and compare them." => "在 GrapeCompare 中打开并比较两个文件。",
  "Ours" => "我方", "Output" => "输出", "Overlay" => "叠加", "Patch" => "补丁", "Path" => "路径",
  "Previous hunk" => "上一个差异块", "Previous search result" => "上一个搜索结果", "Reading Git repository…" => "正在读取 Git 仓库…",
  "References" => "引用", "Removed" => "已移除", "Renamed" => "已重命名", "Repository" => "仓库", "Reset" => "重置",
  "Resolve every conflict before export" => "导出前请解决所有冲突", "Right image" => "右侧图片",
  "Right image opacity" => "右侧图片不透明度", "Right: %1$lld×%2$lld" => "右侧：%1$lld×%2$lld", "Rules" => "规则",
  "Save Failed" => "保存失败", "Save Merge and Close" => "保存合并并关闭", "Save Right" => "保存到右侧", "Save and Continue" => "保存并继续", "Save changes before leaving?" => "离开前保存更改？",
  "Search" => "搜索", "Search both files" => "搜索两侧文件", "Side by Side" => "并排",
  "Structured Values Are Equivalent" => "结构化值等价", "The editable output contains changes that have not been saved." => "可编辑输出包含尚未保存的更改。",
  "The right-side file changed on disk. Compare again before saving." => "磁盘上的右侧文件已更改，请重新比较后再保存。",
  "The selected repository states are equivalent." => "所选仓库状态等价。", "Theirs" => "对方", "Three-Way Merge" => "三方合并",
  "To revision, INDEX, or WORKTREE" => "目标版本、INDEX 或 WORKTREE", "Type Changed" => "类型已更改",
  "Unable to Load Image" => "无法载入图片", "Unmerged" => "未合并", "Untracked" => "未跟踪",
  "Use Left" => "使用左侧", "Use Right" => "使用右侧", "Whitespace" => "空白", "Wrap" => "自动换行", "from %@" => "来自 %@"
}

path = ARGV.fetch(0)
document = REXML::Document.new(File.read(path))
document.elements.each("//trans-unit") do |unit|
  next if unit.elements["target"]
  source = unit.elements["source"]&.text
  next if source.nil? || source.strip.empty? || source == "GrapeCompare"
  value = translations.fetch(source) { abort("Missing translation: #{source}") }
  target = REXML::Element.new("target")
  target.add_attribute("state", "translated")
  target.text = value
  unit.add_element(target)
end
File.write(path, document.to_s)
