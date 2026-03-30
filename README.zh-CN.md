<div align="center">

# Default Browser Switcher

[English](README.md) · **简体中文** · [日本語](README.ja-JP.md)

**一个轻量的 macOS 菜单栏工具，适合那些常同时开着不止一个浏览器、也希望默认浏览器能跟着工作流一起切换的人。**

**当你的工作节奏在 Safari、Arc、Chrome、Firefox 或别的浏览器之间来回切换时，不用反复钻进系统设置，也能更快把链接默认打开方式切到当前想用的那一个。**

</div>

## 项目缘起

现在的 Mac 使用方式，很少再只围着一个浏览器展开。一个浏览器常驻工作账号，另一个已经开好了某个项目需要的标签页，另一个更适合调试，还有一个只是刚好更适合接下来几个小时的任务。这样的切换一旦变成日常，修改默认浏览器就不再是一次性的设置动作，而会变成一种频繁、琐碎又容易打断节奏的小麻烦。

`Default Browser Switcher` 就是为这种日常切换准备的。它提供了一种更快、更贴近原生体验的方式，让你在工作重心变化时顺手切换默认浏览器。这样从应用、工具或系统入口点开的链接，更自然地落到你此刻真正想用的浏览器里，而不是先把你拉去做一轮设置收尾。

## 你可以做什么

- 直接从菜单栏查看当前默认浏览器。
- 一键切换到另一款已安装浏览器。
- 刷新浏览器发现结果，重新读取当前默认浏览器状态和可选浏览器列表。
- 在 `LaunchServices Direct` 和 `System Prompt` 两种切换模式之间选择。
- 配置是否在登录时自动启动。

## 设置说明

你可以从菜单栏里的 `设置…` 打开应用设置。

- `默认网页浏览器`：选择希望系统链接默认打开到哪一个浏览器。
- `刷新当前浏览器`：重新读取当前系统发现结果，同步更新当前默认浏览器显示和可选浏览器列表。切换后、安装或移除浏览器后，或者状态看起来不对时，都可以用它重新确认最新状态。
- `切换模式`：在两种实现之间切换。
  - `LaunchServices Direct` 是默认值。它会直接改写当前用户的 LaunchServices 浏览器处理器，通常更快，也通常不会出现 macOS 的确认弹框。
  - `System Prompt` 使用 macOS 官方 API，更保守，但 macOS 可能会要求你确认浏览器切换。
- `登录时启动`：控制应用是否在你登录系统时自动启动。

如果之后想切换实现方式，只需要从菜单栏打开 `设置…`，然后修改 `切换模式` 选项即可。

## 本地开发

构建：

```bash
xcodebuild -scheme DefaultBrowserSwitcher -project DefaultBrowserSwitcher.xcodeproj -destination 'platform=macOS' build
```

测试：

```bash
xcodebuild test -scheme DefaultBrowserSwitcher -project DefaultBrowserSwitcher.xcodeproj -destination 'platform=macOS'
```

可选验证：

```bash
bash Scripts/verify-s01.sh
bash Scripts/verify-s02.sh
```

## License

[MIT](LICENSE)
