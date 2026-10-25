# 源码构建（维护者）

普通用户请下载 Releases 的编译包，按 [INSTALL.md](INSTALL.md) 使用。

## 依赖

- Apple Silicon Mac，完整 Xcode 和 macOS SDK。
- SwiftUI、AppKit、Foundation、CryptoKit，均来自系统 / Xcode，没有第三方 Swift 包。
- 发布打包脚本使用 Python 3 标准库和 macOS 自带的 codesign。

## 编译

```sh
chmod +x build.sh
./build.sh
```

默认输出 `.build/app/定位控制台.app`。需要其他输出目录时传第一个参数：

```sh
./build.sh ./dist/local
```

构建脚本默认使用 `/Applications/Xcode.app/Contents/Developer`。有不同安装位置时，设置自己的 `DEVELOPER_DIR`；构建缓存位置可通过 `LOCATION_CONSOLE_BUILD_DIR` 指定。

编译目标为 arm64、macOS 14.0；最低加载版本不等于 Xcode 设备工具的实际运行范围。实际能力在应用「环境检查」中按命令支持情况判断。

## 打包

```sh
python3 scripts/package_release.py
```

脚本会编译、临时签名，并在 `dist/` 生成下载包、源码包、SHA-256、发布说明和发布清单。也可指定已经构建的软件：

```sh
python3 scripts/package_release.py --app ./dist/local/定位控制台.app
```

完整参数用 `python3 scripts/package_release.py --help` 查看。打包脚本不会启动应用、操纵手机、运行回放或进行首次安装体验。

## iPhone 配套项目

`iPhone-定位诊断/` 独立构建，需要使用者自己的开发团队签名。仓库中不保存个人 Team、证书或设备配置。它是可选的诊断工具，Mac 核心功能不依赖安装它。
