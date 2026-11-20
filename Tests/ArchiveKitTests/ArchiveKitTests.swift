//
//  ArchiveKitTests.swift
//  ArchiveKitTests
//

import XCTest
@testable import ArchiveKit

final class ArchiveKitTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bz-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory = workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    private func makeSampleTree() throws -> URL {
        let source = workDirectory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("sub", isDirectory: true),
                                                withIntermediateDirectories: true)
        try "hello bandizip\n".write(to: source.appendingPathComponent("hello.txt"),
                                     atomically: true, encoding: .utf8)
        try "世界\n".write(to: source.appendingPathComponent("sub").appendingPathComponent("world.txt"),
                           atomically: true, encoding: .utf8)
        return source
    }

    func testSupportedFormatsContainZip() throws {
        let formats = ArchiveService.shared.availableFormats()
        XCTAssertTrue(formats.contains(.zip))
        XCTAssertTrue(formats.contains(.tarGz))
    }

    func testZipRoundTrip() throws {
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("sample.zip")

        try ArchiveService.shared.create(items: [source], destination: archive, format: .zip, level: 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let listing = try ArchiveService.shared.list(archiveAt: archive)
        XCTAssertEqual(listing.fileCount, 2)
        XCTAssertFalse(listing.isEncrypted)
        XCTAssertTrue(listing.totalSize > 0)

        let destination = workDirectory.appendingPathComponent("out-zip", isDirectory: true)
        try ArchiveService.shared.extract(archiveAt: archive,
                                          to: destination,
                                          policy: .overwrite,
                                          totalHint: listing.totalSize)

        let content = try String(contentsOf: destination.appendingPathComponent("src/hello.txt"), encoding: .utf8)
        XCTAssertEqual(content, "hello bandizip\n")

        let nested = try String(contentsOf: destination.appendingPathComponent("src/sub/world.txt"), encoding: .utf8)
        XCTAssertEqual(nested, "世界\n")
    }

    func testTarGzRoundTrip() throws {
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("sample.tar.gz")

        try ArchiveService.shared.create(items: [source], destination: archive, format: .tarGz, level: 6)
        let listing = try ArchiveService.shared.list(archiveAt: archive)
        XCTAssertEqual(listing.fileCount, 2)

        let destination = workDirectory.appendingPathComponent("out-tgz", isDirectory: true)
        try ArchiveService.shared.extract(archiveAt: archive, to: destination, policy: .overwrite)
        let content = try String(contentsOf: destination.appendingPathComponent("src/sub/world.txt"), encoding: .utf8)
        XCTAssertEqual(content, "世界\n")
    }

    func testPasswordProtectedZip() throws {
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("secret.zip")

        try ArchiveService.shared.create(items: [source],
                                         destination: archive,
                                         format: .zip,
                                         level: 5,
                                         password: "pw123")

        let destination = workDirectory.appendingPathComponent("out-secret", isDirectory: true)

        // 错误密码应当失败，并标记为「需要密码」
        XCTAssertThrowsError(try ArchiveService.shared.extract(archiveAt: archive,
                                                               to: destination,
                                                               policy: .overwrite,
                                                               password: "wrong")) { error in
            guard let archiveError = error as? ArchiveError else {
                return XCTFail("错误类型不对：\(error)")
            }
            XCTAssertTrue(archiveError.needsPassword)
        }

        // 正确密码可以解出内容
        try ArchiveService.shared.extract(archiveAt: archive,
                                          to: destination,
                                          policy: .overwrite,
                                          password: "pw123")
        let content = try String(contentsOf: destination.appendingPathComponent("src/hello.txt"), encoding: .utf8)
        XCTAssertEqual(content, "hello bandizip\n")
    }

    func testSevenZipWhenAvailable() throws {
        guard ArchiveService.shared.availableFormats().contains(.sevenZip) else {
            throw XCTSkip("当前系统 libarchive 不支持 7z 写入")
        }
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("sample.7z")

        try ArchiveService.shared.create(items: [source], destination: archive, format: .sevenZip, level: 5)
        let listing = try ArchiveService.shared.list(archiveAt: archive)
        XCTAssertEqual(listing.fileCount, 2)

        let destination = workDirectory.appendingPathComponent("out-7z", isDirectory: true)
        try ArchiveService.shared.extract(archiveAt: archive, to: destination, policy: .overwrite)
        let content = try String(contentsOf: destination.appendingPathComponent("src/hello.txt"), encoding: .utf8)
        XCTAssertEqual(content, "hello bandizip\n")
    }

    func testOnlySelectedPathsAreExtracted() throws {
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("partial.zip")
        try ArchiveService.shared.create(items: [source], destination: archive, format: .zip, level: 5)

        let destination = workDirectory.appendingPathComponent("out-partial", isDirectory: true)
        try ArchiveService.shared.extract(archiveAt: archive,
                                          to: destination,
                                          policy: .overwrite,
                                          onlyPaths: ["src/hello.txt"])

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("src/hello.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("src/sub/world.txt").path))
    }

    func testOverwritePolicies() throws {
        let source = try makeSampleTree()
        let archive = workDirectory.appendingPathComponent("policy.zip")
        try ArchiveService.shared.create(items: [source], destination: archive, format: .zip, level: 5)

        let destination = workDirectory.appendingPathComponent("out-policy", isDirectory: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "old\n".write(to: destination.appendingPathComponent("src/hello.txt"), atomically: true, encoding: .utf8)

        // 跳过：保留旧内容
        try ArchiveService.shared.extract(archiveAt: archive, to: destination, policy: .skip)
        var content = try String(contentsOf: destination.appendingPathComponent("src/hello.txt"), encoding: .utf8)
        XCTAssertEqual(content, "old\n")

        // 覆盖：写入新内容
        try ArchiveService.shared.extract(archiveAt: archive, to: destination, policy: .overwrite)
        content = try String(contentsOf: destination.appendingPathComponent("src/hello.txt"), encoding: .utf8)
        XCTAssertEqual(content, "hello bandizip\n")
    }

    func testNamingHelpers() {
        XCTAssertEqual(ArchiveNaming.baseName(for: URL(fileURLWithPath: "/tmp/report.tar.gz")), "report")
        XCTAssertEqual(ArchiveNaming.baseName(for: URL(fileURLWithPath: "/tmp/photo.zip")), "photo")

        let destination = ArchiveNaming.uniqueDestination(in: workDirectory, baseName: "unique-test", fileExtension: "zip")
        XCTAssertEqual(destination.lastPathComponent, "unique-test.zip")
    }
}
