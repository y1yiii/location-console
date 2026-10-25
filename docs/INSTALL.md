# 下载与首次配置

## 1. 下载正确的软件包

在仓库的 Releases 页面下载 `LocationConsole-v版本-macOS-arm64.zip`。解压后将整个「定位控制台.app」放到「应用程序」，不要只取出其中的可执行文件。

当前包面向 Apple Silicon Mac，需要兼容的完整 Xcode。Windows、Android 和 Intel Mac 不在此二进制的支持范围内。完整兼容状态见 [COMPATIBILITY.md](COMPATIBILITY.md)。

## 2. 准备 Xcode

1. 从 [Apple 官方渠道](https://developer.apple.com/xcode/)获取完整 Xcode。
2. 由你本人打开 Xcode，按其提示完成许可、所需平台和组件安装。不要把 Apple 账号密码或验证码提供给他人。
3. Xcode 可关闭；定位控制台调用其设备工具。Xcode 及相关组件应保留在 Mac 上。

软件会查找 `/Applications/Xcode.app`，也会检查常见应用目录中的其他 Xcode。使用非默认位置时，可在软件的「环境检查」选择自己的 Xcode。

## 3. 打开定位控制台

首次会显示「环境检查」。点击「检查环境与设备」，逐项查看：

| 检查项 | 通过表示 |
|---|---|
| Mac 与系统 | 本机构架和应用最低加载要求匹配 |
| 完整 Xcode | 能找到设备工具并读取 Xcode 版本 |
| Xcode 首次初始化 | Xcode 报告首次准备任务已完成 |
| 固定定位接口 | 当前 Xcode 提供所需固定坐标参数 |
| 路线回放接口 | 当前 Xcode 提供带速度与路线文件的接口 |
| 清除模拟接口 | 当前 Xcode 提供清除命令 |

这些步骤只读取信息，不会启动模拟、自动接受 Xcode 许可或安装组件。可以随时取消检查。

### macOS 阻止首次打开

当前 Beta 包尚未做 Developer ID 签名和 Apple 公证。请核对下载来源和 Release 提供的 SHA-256；如果系统阻止打开，按 [Apple 官方说明](https://support.apple.com/en-us/102445)判断并处理。校验和只能帮助比对文件完整性，不能替代可信发布来源或签名。

本项目没有提供关闭 Gatekeeper、删除隔离标记或绕过恶意软件检测的脚本。若系统报告软件损坏或可能危害电脑，停止使用并向维护者反馈。

## 4. 准备 iPhone

1. 用支持数据传输的数据线连接，保持 iPhone 解锁。
2. 在 iPhone 上确认信任这台 Mac。
3. 在「设置 → 隐私与安全性 → 开发者模式」启用，按提示重启并再次确认。
4. 如果没有开发者模式入口，先用 Xcode 的设备窗口选择这台手机，完成开发准备，再查看设置。不同 Xcode 版本的设备窗口名称可能不同。
5. 回到定位控制台刷新设备，选择这台 iPhone。

[Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

手机检查显示已配对和开发者模式已开启后，仍需保持解锁。设备是否能接受定位命令，以实际操作结果为准。

## 5. 开始使用

- 固定定位：输入 WGS84 纬度、经度，点击应用。
- 路线回放：导入一条连续 GPX，选择保存的路线，确认总耗时后开始。默认每公里 5分00秒。
- 到达后先结束其他 App 中的记录，再点击「停止并清除」。在手机地图点「当前位置」，确认蓝点恢复。仍残留时可重启 iPhone。

配套 iPhone「定位诊断」是可选工具，不是普通回放的安装前置条件。
