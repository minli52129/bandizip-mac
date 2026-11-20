//
//  CompressSheet.swift
//  BandizipMac
//

import SwiftUI
import AppKit
import ArchiveKit

struct CompressSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CompressDraft

    init(draft: CompressDraft) {
        _draft = State(initialValue: draft)
    }

    private var canStart: Bool {
        !draft.items.isEmpty && !(draft.usePassword && draft.password.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: "新建压缩包",
                         subtitle: "\(draft.items.count) 个项目 · 原始大小 \(Fmt.bytes(draft.estimatedSize))",
                         icon: "doc.zipper")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSection(title: "包含的项目") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(draft.items.prefix(6).indices), id: \.self) { index in
                                itemRow(draft.items[index])
                            }
                            if draft.items.count > 6 {
                                Text("… 等共 \(draft.items.count) 个项目")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.tertiaryText)
                                    .padding(.leading, 2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.separator, lineWidth: 1)
                        )
                    }

                    FormSection(title: "压缩格式") {
                        Picker("", selection: Binding(get: { draft.format }, set: { applyFormat($0) })) {
                            ForEach(state.availableFormats) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(draft.format.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    if draft.format.supportsLevel {
                        FormSection(title: "压缩级别") {
                            HStack(spacing: 10) {
                                Slider(value: Binding(get: { Double(draft.level) }, set: { draft.level = Int($0.rounded()) }),
                                       in: 1...9,
                                       step: 1)
                                Text(state.preferences.levelLabel(draft.level))
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 62, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }

                    FormSection(title: "密码保护") {
                        if draft.format.supportsPassword {
                            Toggle("使用密码加密", isOn: $draft.usePassword)
                                .toggleStyle(.checkbox)
                            if draft.usePassword {
                                SecureField("请输入密码", text: $draft.password)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 260)
                            }
                        } else {
                            Text("\(draft.format.displayName) 不支持密码保护")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }

                    FormSection(title: "保存位置") {
                        HStack(spacing: 8) {
                            Text(draft.destination.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Theme.separator, lineWidth: 1)
                                )

                            Button("更改…") {
                                chooseDestination()
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("开始压缩") {
                    let finalDraft = draft
                    dismiss()
                    state.startCompress(finalDraft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 580, height: 580)
        .background(Theme.windowBackground)
    }

    private func itemRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isDirectory(url) ? "folder.fill" : "doc.fill")
                .font(.system(size: 10))
                .foregroundStyle(isDirectory(url) ? Theme.accent : Theme.secondaryText)
                .frame(width: 14)
            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(isDirectory(url) ? "文件夹" : fileSizeText(url))
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .monospacedDigit()
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &flag)
        return flag.boolValue
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return "—" }
        return Fmt.bytes(size.int64Value)
    }

    private func applyFormat(_ format: ArchiveFormat) {
        guard format != draft.format else { return }
        let base = draft.items.count == 1 ? AppState.baseName(for: draft.items[0]) : "归档"
        let directory = draft.destination.deletingLastPathComponent()
        draft.format = format
        draft.destination = directory.appendingPathComponent("\(base).\(format.fileExtension)")
        if !format.supportsPassword {
            draft.usePassword = false
            draft.password = ""
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "保存压缩包"
        panel.prompt = "保存"
        panel.directoryURL = draft.destination.deletingLastPathComponent()
        panel.nameFieldStringValue = draft.destination.lastPathComponent

        if panel.runModal() == .OK, let url = panel.url {
            draft.destination = url
        }
    }
}
