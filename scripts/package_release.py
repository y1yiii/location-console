#!/usr/bin/env python3
"""Build release assets and export only public project files. No upload or device actions."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
TOP = ["README.md", "LICENSE", "VERSION", "CHANGELOG.md", "build.sh", "Icon.swift", "使用说明.md", ".gitignore"]
TREES = ["Sources/*.swift", "Resources/Info.plist", "docs/*.md", "scripts/package_release.py", ".github/ISSUE_TEMPLATE/*.yml"]
COMPANION = [
    "iPhone-定位诊断/LocationProbe.swift", "iPhone-定位诊断/Info.plist", "iPhone-定位诊断/安装说明.md",
    "iPhone-定位诊断/LocationProbe.xcodeproj/project.pbxproj",
    "iPhone-定位诊断/LocationProbe.xcodeproj/xcshareddata/xcschemes/LocationProbe.xcscheme",
]


def public_files() -> list[Path]:
    files = [ROOT / item for item in TOP + COMPANION]
    for pattern in TREES:
        matches = sorted(ROOT.glob(pattern))
        if not matches:
            raise RuntimeError(f"缺少发布文件：{pattern}")
        files.extend(matches)
    for path in files:
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(ROOT):
            raise RuntimeError(f"发布路径不安全或文件缺失：{path.name}")
        if path.suffix == ".pbxproj":
            teams = re.findall(r"DEVELOPMENT_TEAM\s*=\s*(.*?);", path.read_text())
            if any(value.strip() != '\"\"' for value in teams):
                raise RuntimeError("配套项目存在非空个人开发团队，已停止导出。")
    return sorted(set(files))


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="使用已构建的应用；省略时先构建")
    parser.add_argument("--output", type=Path, default=ROOT / "dist", help="发布附件目录")
    parser.add_argument("--repository", type=Path, help="可选：导出干净源码目录；不能覆盖已有目录")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[a-z0-9.]+)?", version):
        raise RuntimeError("VERSION 格式无效。")
    output = args.output.resolve()
    repository = args.repository.resolve() if args.repository else None
    if repository and (repository.exists() or repository == ROOT or ROOT.is_relative_to(repository)):
        raise RuntimeError("源码导出目录已存在或不安全，请指定新的目录。")
    files = public_files()
    output.mkdir(parents=True, exist_ok=True)
    prefix = f"LocationConsole-v{version}"
    app_zip = output / f"{prefix}-macOS-arm64.zip"
    source_zip = output / f"{prefix}-source.zip"
    with tempfile.TemporaryDirectory(prefix="LocationConsole-release-") as temp_name:
        temp = Path(temp_name)
        app = args.app.resolve() if args.app else temp / "build" / "定位控制台.app"
        if not args.app:
            run("/bin/zsh", str(ROOT / "build.sh"), str(app.parent))
        required = [app / "Contents/Info.plist", app / "Contents/MacOS/LocationConsole", app / "Contents/Resources/AppIcon.icns", app / "Contents/Resources/LICENSE"]
        if not all(path.is_file() for path in required):
            raise RuntimeError("应用结构不完整，请重新构建。")
        with required[0].open("rb") as handle:
            info = plistlib.load(handle)
        if info.get("CFBundleShortVersionString") != version.split("-", 1)[0] or info.get("CFBundleIdentifier") != "org.localdiagnostics.LocationConsole":
            raise RuntimeError("应用版本或 Bundle ID 与发布目标不一致。")
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        signature_info = subprocess.run(["/usr/bin/codesign", "-dv", str(app)], text=True, capture_output=True, check=True)
        signature = "ad-hoc" if "Signature=adhoc" in signature_info.stderr else "other-signature"
        bundle = temp / "download"
        bundle.mkdir()
        shutil.copytree(app, bundle / "定位控制台.app")
        shutil.copy2(ROOT / "LICENSE", bundle / "LICENSE")
        quickstart = (
            f"# 定位控制台 v{version}\n\n"
            "1. 将整个「定位控制台.app」放入「应用程序」。\n"
            "2. 安装并打开完整 Xcode，完成其许可和组件准备。\n"
            "3. 打开软件，在「环境检查」检查 Xcode 与接口。\n"
            "4. USB 连接 iPhone，解锁、信任 Mac、开启开发者模式，刷新设备。\n"
            "5. 选用保存的路线或导入 GPX，确认耗时，再开始回放。\n"
            "6. 完成后停止并清除，在手机地图确认真实位置恢复。\n\n"
            "当前为 Apple Silicon Beta，仍需兼容的完整 Xcode。临时签名、未公证，首次安装体验尚未验收。\n"
            "打开受阻时查看 Apple 说明：https://support.apple.com/en-us/102445\n"
            "环境检查可以导出不含设备标识和路线坐标的报告；分享前请检查。\n"
        )
        (bundle / "开始使用.md").write_text(quickstart)
        # ZIP's UTF-8 filename flag keeps Chinese bundle/resource names
        # readable in both macOS Archive Utility and cross-platform readers.
        # ZipFile.write preserves each regular file's Unix executable mode.
        with ZipFile(app_zip, "w", ZIP_DEFLATED) as archive:
            for path in sorted(bundle.rglob("*")):
                if path.is_symlink():
                    raise RuntimeError("当前应用打包器不接受符号链接，请使用受支持的构建输出。")
                if path.is_file():
                    archive.write(path, path.relative_to(bundle))
        with ZipFile(source_zip, "w", ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, Path("location-console") / path.relative_to(ROOT))
        if repository:
            repository.mkdir(parents=True)
            for path in files:
                target = repository / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        hashes = {path.name: digest(path) for path in (app_zip, source_zip)}
        (output / "SHA256SUMS.txt").write_text("".join(f"{checksum}  {name}\n" for name, checksum in hashes.items()))
        manifest = {
            "version": version, "created_at": datetime.now(timezone.utc).isoformat(), "architecture": "arm64",
            "application_minimum_macos": info.get("LSMinimumSystemVersion"),
            "runtime_requires_compatible_full_xcode": True, "signature": signature,
            "notarization": "not_performed_by_this_script", "first_install_experience": "not_performed",
            "location_replay_during_packaging": "not_performed", "artifact_sha256": hashes,
            "source_file_count": len(files),
        }
        (output / "release-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        (output / "RELEASE_NOTES.md").write_text(
            f"# 定位控制台 v{version}\n\n"
            "GitHub 预发布版，面向 Apple Silicon Mac 通过 USB 控制 iPhone。\n\n"
            "## 本次更新\n\n"
            "- 首次环境检查与 Xcode 自动发现。\n- Xcode 初始化、固定定位、路线回放、清除接口检查。\n"
            "- 手机配对与开发者模式准备提示。\n- 可导出不含设备标识、设备名称和路线坐标的环境报告。\n"
            "- 保留多路线保存/选用/删除和几分几秒的配速显示。\n\n"
            f"普通用户下载 `{app_zip.name}`；源码快照为 `{source_zip.name}`。\n\n"
            "## 运行条件与发布状态\n\n"
            "需要兼容的完整 Xcode、已配对并开启开发者模式的 iPhone。应用最低加载版本不等于 Xcode 的系统要求。\n\n"
            f"本包签名类型：{signature}。本次脚本未执行 Apple 公证、首次安装体验或定位回放。\n"
            "请标记为 Pre-release，并保留这些未覆盖范围。当前不保证第三方运动 App 认可里程。\n"
        )
    print(f"发布附件：{output}")
    if repository:
        print(f"干净源码目录：{repository}")
    print("未创建或上传 GitHub 仓库；未进行首次安装体验和定位回放。")


if __name__ == "__main__":
    main()
