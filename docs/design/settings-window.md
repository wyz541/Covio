# 设置窗口

## 目标

Covio 的设置窗口遵循 macOS 原生 Settings 模式。
窗口由系统管理，分页在工具栏切换，内容使用标准分组表单。

## 结构

```text
Settings 场景
└── 原生分页工具栏
    ├── 概览
    ├── 电池
    ├── 闲置
    ├── 剪贴板
    ├── 助手
    └── 通用
```

工具栏固定显示，不开放自定义。
工具栏始终标出当前分页。
窗口标题显示当前分页名称。
重新打开窗口时恢复上次使用的分页。

窗口尺寸固定。
用户可以关闭和移动窗口。
最小化按钮和缩放按钮禁用。

## 内容

常规设置使用 `Form` 和 grouped 样式。
开关、选择器、数字输入和按钮使用系统控件。
分组间距、圆角和底材由系统提供。
复杂的助手内容使用标准材质，不使用内容层 Liquid Glass。

搜索框放在系统工具栏。
搜索结果浮在当前分页上方。
用户选择搜索结果后，窗口切换到对应分页并滚动到目标行。

## Liquid Glass 边界

Liquid Glass 只用于系统工具栏、搜索框和标准交互控件。
设置内容层使用标准材质。
不在表单、卡片和列表上重复叠加 Liquid Glass。

## 依据

- [Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Apple HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [SwiftUI Settings](https://developer.apple.com/documentation/swiftui/settings)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
