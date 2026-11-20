//
//  BandizipMacApp.swift
//  BandizipMac
//

import SwiftUI
import AppKit

@main
struct BandizipMacApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup("Bandizip") {
            MainView()
                .environmentObject(state)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开压缩包…") {
                    AppState.shared.promptOpen()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("新建压缩包…") {
                    AppState.shared.promptNewArchive()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Divider()

                Button("解压…") {
                    AppState.shared.promptExtract(selectionOnly: false)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("解压所选…") {
                    AppState.shared.promptExtract(selectionOnly: true)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("校验压缩包") {
                    AppState.shared.testCurrentArchive()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("关闭压缩包") {
                    AppState.shared.closeArchive()
                }

                Button("在 Finder 中显示") {
                    AppState.shared.revealArchiveInFinder()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder 双击 / 拖到 Dock 图标 / open -a 时触发
    func application(_ application: NSApplication, open urls: [URL]) {
        AppState.shared.handleOpenURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
