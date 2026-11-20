// swift-tools-version: 5.9
// Bandizip for Mac —— 一个仿 Bandizip 的 macOS 压缩软件
// 真正的编译在 GitHub Actions (macOS runner) 上完成，本仓库不依赖 Xcode 工程。

import PackageDescription

let package = Package(
    name: "BandizipMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BandizipMac", targets: ["BandizipMac"]),
        .executable(name: "bz", targets: ["bz"]),
        .library(name: "ArchiveKit", targets: ["ArchiveKit"])
    ],
    targets: [
        // libarchive 的极薄 C 桥接层：读写压缩包、解压、进度/取消回调
        .target(
            name: "CArchive",
            path: "Sources/CArchive",
            publicHeadersPath: "include",
            cSettings: [
                // macOS SDK 不再提供 <archive.h>，这里内置 libarchive 3.7.4 的头文件，
                // 运行时链接系统自带的 libarchive dylib（dyld shared cache）。
                .headerSearchPath("vendor")
            ],
            linkerSettings: [
                .linkedLibrary("archive"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("lzma"),
                .linkedLibrary("iconv")
            ]
        ),
        .target(
            name: "ArchiveKit",
            dependencies: ["CArchive"],
            path: "Sources/ArchiveKit"
        ),
        .executableTarget(
            name: "BandizipMac",
            dependencies: ["ArchiveKit"],
            path: "Sources/BandizipMac"
        ),
        .executableTarget(
            name: "bz",
            dependencies: ["ArchiveKit"],
            path: "Sources/bz"
        ),
        .testTarget(
            name: "ArchiveKitTests",
            dependencies: ["ArchiveKit"],
            path: "Tests/ArchiveKitTests"
        )
    ]
)
