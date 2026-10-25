# GitHub 发布步骤（维护者）

当前目标是可下载的 GitHub Beta。首次安装体验验收按项目安排暂未执行，发布说明必须保留这一状态。

## 1. 准备源码

- 核对 `VERSION`、应用 Info.plist、README 和版本记录。
- 当前为 MIT 许可证，版权标识为 Location Console contributors。首次公开前可以按项目归属调整版权署名或许可证。
- 只发布整理后的项目目录。不要把原始工作目录、应用数据目录、个人 GPX、日志、证书或账号信息上传。

## 2. 构建并导出发布目录

```sh
python3 scripts/package_release.py --repository ./dist/location-console
```

输出包括：

- `LocationConsole-v版本-macOS-arm64.zip`：普通用户下载，包含应用、快速开始和许可证。
- `LocationConsole-v版本-source.zip`：按允许列表生成的源码快照。
- `SHA256SUMS.txt`：上述两个压缩包的校验和。
- `release-manifest.json`：版本、构架、签名信息和未进行的验证范围。
- `RELEASE_NOTES.md`：可用于 GitHub Release 的说明。
- `location-console/`：可独立成为 GitHub 仓库的干净目录，不含本机运行数据。

`--repository` 不覆盖已存在目录；重新导出请使用一个新的空路径。压缩包和 dist 构建产物不应提交到源码仓库，应作为 Release 附件上传。

## 3. 上传 GitHub

1. 创建自己的仓库，将导出的源码目录内容提交进去。
2. 创建与 `VERSION` 对应的标签和 Release。
3. Beta 版本标记为 **Pre-release**，正文使用生成的 `RELEASE_NOTES.md`。
4. 附上软件包、源码快照、SHA256SUMS 和 release-manifest。
5. 确认 README 的下载文件名与附件一致。

这些步骤由维护者在准备公开时执行。打包脚本不会创建仓库、上传文件或发布 Release。

## 签名状态

当前构建使用本机临时签名，未做 Apple 公证。打包脚本进行的是包结构、版本和代码签名完整性检查，不代表 Gatekeeper 首次下载启动体验已通过。正式 Developer ID 签名、公证及首次安装体验需另行安排。

[Apple Developer ID 分发说明](https://developer.apple.com/developer-id/)
