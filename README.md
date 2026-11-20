# Bandizip for Mac

一个仿 [Bandizip](https://www.bandisoft.com/bandizip/) 的 macOS 压缩软件。原生 SwiftUI 界面，底层用系统自带的 `libarchive` 读写压缩包，**编译与打包全部放在 GitHub Actions 上完成**，本机不需要 Xcode 工程，也不需要手动装依赖。

```
┌──────────────────────────────────────────────────────────────┐
│ 打开   解压  解压所选  新建  校验 │ 位置  关闭       🔍 搜索   │
├────────────┬─────────────────────────────────────────────────┤
│ 快速访问   │ report.zip ▸ assets                              │
│  个人文件夹│ ┌───────────────────────────────────────────┐   │
│  桌面      │ │ 名称           大小    压缩率   修改日期  │   │
│  下载      │ │ 📁 assets       —       —      2026/03/11 │   │
│  文稿      │ │ 📄 README.md   4.2 KB   32%    2026/03/11 │   │
│            │ │ 📦 bundle.zip  1.1 MB   68%    2026/03/10 │   │
│ 最近打开   │ └───────────────────────────────────────────┘   │
│ 支持格式   │ 12 个文件 · 3 个文件夹   原始 8.4 MB · 压缩率 41%│
└────────────┴─────────────────────────────────────────────────┘
```

## 功能

- **打开任意格式**：ZIP / 7Z / RAR / TAR / GZ / BZ2 / XZ / ISO / CAB / ALZ / EGG / JAR / APK …（读取能力来自 libarchive）
- **像文件管理器一样浏览**：双击进入子目录、面包屑导航、返回上一级、按名称 / 大小 / 日期排序、实时搜索过滤
- **解压**：全部解压或只解压选中项；同名文件支持「覆盖 / 跳过 / 自动重命名 / 逐项询问」；解压到同名子文件夹、同目录或任意位置
- **压缩**：ZIP / 7Z / TAR / TAR.GZ / TAR.BZ2 / TAR.XZ，1–9 级压缩，ZIP 与 7Z 支持密码
- **加密包**：自动识别加密条目，缺少密码时弹窗索取，密码错误给出中文提示并允许重试
- **直接预览**：双击压缩包内的文件，会解压到临时目录并交给系统默认程序打开
- **进度与取消**：实时百分比、速度、剩余时间，可随时中断
- **完整性校验**：相当于 Bandizip 的「测试」，完整解压一遍并报告错误
- **Finder 集成**：注册为压缩包的「打开方式」，支持双击打开、拖到 Dock 图标打开、`open -a`
- **拖放**：把压缩包拖进窗口直接打开；拖入普通文件 / 文件夹立刻进入压缩流程
- **命令行工具 `bz`**：随 App 一起打包，`l` / `x` / `c` / `t` / `f` 五个子命令

## 从 GitHub Actions 获取安装包

仓库推上去后，工作流 `.github/workflows/build.yml` 会：

1. 在 `macos-14` runner 上 `swift test` 跑单元测试；
2. 交叉编译 **arm64 + x86_64 通用二进制**；
3. 组装 `BandizipMac.app`、生成 `.icns` 图标、ad-hoc 签名；
4. 产出 `BandizipMac-<版本>.dmg`、`BandizipMac-<版本>.zip` 和 `SHA256SUMS.txt`；
5. 上传为 Artifact；如果提交是 `v*` 标签，还会自动创建 Release 并附上安装包。

下载方式：**Actions → 选一次构建 → 底部 Artifacts**，或直接看 **Releases**。

> 打 tag 触发正式发布：
> ```bash
> git tag v1.0.0 && git push origin v1.0.0
> ```

### 首次打开被 Gatekeeper 拦下怎么办

安装包是 ad-hoc 签名（没有 Apple 开发者证书，也没有公证），所以首次打开会提示「无法验证开发者」：

- 方式一：在 Finder 里 **右键 → 打开 → 打开**；
- 方式二：终端执行
  ```bash
  xattr -dr com.apple.quarantine /Applications/Bandizip.app
  ```

## 命令行 `bz`

App 内部自带一份，也可以直接调用：

```bash
bz l archive.zip                 # 列出内容
bz x archive.zip -o ~/Desktop    # 解压到指定目录
bz x archive.zip --skip          # 跳过同名文件（还有 --overwrite / --rename）
bz x secret.zip -p 1234          # 带密码解压
bz c out.zip ~/Photos ~/notes.md # 压缩
bz c out.7z ~/Photos -l 9 -p 1234
bz t archive.zip                 # 完整性校验
bz f                             # 查看本机支持的格式
```

## 工程结构

```
Package.swift                    SwiftPM 清单（3 个 target + 测试）
Sources/CArchive/                libarchive 极薄 C 桥接层（读写、进度、取消、路径消毒）
  ├─ include/carchive.h          对外只暴露 void*，避开不完整结构体的导入差异
  ├─ carchive.c                  解压走 archive_write_disk，压缩走 archive_write_*
  └─ vendor/archive*.h           内置 libarchive 3.7.4 头文件（macOS SDK 已不再提供）
Sources/ArchiveKit/              Swift 封装：ArchiveService / ArchiveEntry / ArchiveFormat
Sources/BandizipMac/             SwiftUI 应用（主窗口、压缩/解压面板、进度、设置）
Sources/bz/main.swift            命令行工具
Tests/ArchiveKitTests/           往返、密码、覆盖策略、只解压选中项等测试
Tools/gen_icon.py                纯 Python 生成图标（SDF + 抗锯齿，无第三方库）
scripts/package.sh               编译 → 组装 .app → 图标 → 签名 → DMG/ZIP
.github/workflows/build.yml      CI：测试 + 通用二进制 + 产物/发布
```

### 几个实现要点

- **不依赖第三方 Swift 包**：压缩能力直接调用 `libarchive`（macOS 自带 dylib，走 dyld shared cache）。macOS SDK 从某个版本起不再带 `archive.h`，所以仓库内嵌了官方头文件，用 `.headerSearchPath("vendor")` 引入。
- **解压路径安全**：自己做了路径消毒（去掉绝对路径、`.`、`..`），并开启 `ARCHIVE_EXTRACT_SECURE_SYMLINKS | SECURE_NODOTDOT`，避免 Zip Slip。目标目录先做 `realpath`，否则 macOS 上 `/tmp` 这类符号链接会被安全策略拒绝。
- **进度与取消**：C 层通过函数指针回调字节数，Swift 用 `CallbackBox` + `Unmanaged` 传上下文；取消靠每处理一个数据块检查一次标志位。
- **7Z 是否可用由运行时探测**：`bz_format_supported()` 会真的尝试创建 writer，所以在不支持的系统上 UI 会自动隐藏该格式，而不是点了报错。

## 本地开发（可选）

CI 是唯一的发布途径，但本机调试也可以：

```bash
swift build            # 调试构建
swift test             # 单元测试（需要完整 Xcode，XCTest 不在 CLT 里）
swift run BandizipMac  # 直接跑界面
./scripts/package.sh   # 本机出 DMG/ZIP
```

需要 macOS 13+ 与 Swift 5.9+。

## 支持情况与已知限制

| 能力 | 状态 |
| --- | --- |
| 读取 ZIP / 7Z / RAR / TAR / GZ / BZ2 / XZ / ISO / CAB 等 | ✅ |
| 写入 ZIP / 7Z / TAR / TAR.GZ / TAR.BZ2 / TAR.XZ | ✅ |
| ZIP 传统加密（ZipCrypto） | ✅ |
| ZIP AES-256 加密 | ❌（libarchive 写入不支持） |
| 分卷压缩 / 分卷读取 | ❌（路线图） |
| 单个条目显示「压缩后大小」 | ❌（libarchive 不暴露该字段，列为 `—`；整体压缩率仍可显示） |
| Apple 公证 / 自动更新 | ❌（需要付费开发者账号） |

## 许可证

MIT。内置的 libarchive 头文件遵循 BSD-2-Clause，详见 [LICENSE](LICENSE)。

Bandizip 是 Bandisoft 的商标，本项目只是学习性质的界面仿写，与 Bandisoft 无关。
