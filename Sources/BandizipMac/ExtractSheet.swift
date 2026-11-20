//
//  ExtractSheet.swift
//  BandizipMac
//

import SwiftUI
import AppKit
import ArchiveKit

struct ExtractSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ExtractDraft
    @State private var passwordInput: String
    @State private var askEachTime: Bool

    init(draft: ExtractDraft) {
        _draft = State(initialValue: draft)
        _passwordInput = State(initialValue: draft.password)
        _askEachTime = State(initialValue: draft.policy == .ask)
    }

    private var effectivePolicy: ExtractPolicy {
        askEachTime ? .ask : draft.policy
    }

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: "解压",
                         subtitle: draft.archiveURL.lastPathComponent,
                         icon: "square.and.arrow.down")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSection(title: "范围") {
                        HStack(spacing: 8) {
                            Image(systemName: draft.onlyPaths == nil ? "doc.zipper" : "checklist")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                            Text(draft.scopeDescription)
                                .font(.system(size: 12))
                            Spacer()
                        }
                    }

                    FormSection(title: "解压到") {
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

                        HStack(spacing: 6) {
                            Button("同目录") {
                                draft.destination = draft.archiveURL.deletingLastPathComponent()
                            }
                            Button("同名文件夹") {
                                let parent = draft.archiveURL.deletingLastPathComponent()
                                draft.destination = parent.appendingPathComponent(AppState.baseName(for: draft.archiveURL), isDirectory: true)
                            }
                            Button("桌面") {
                                let home = FileManager.default.homeDirectoryForCurrentUser
                                draft.destination = home.appendingPathComponent("Desktop")
                            }
                        }
                        .controlSize(.small)
                    }

                    FormSection(title: "同名文件") {
                        Picker("", selection: Binding(get: { draft.policy }, set: { draft.policy = $0; askEachTime = ($0 == .ask) })) {
                            ForEach(ExtractPolicy.allCases) { policy in
                                Text(policy.title).tag(policy)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    FormSection(title: "密码（未加密可留空）") {
                        HStack(spacing: 8) {
                            SecureField("压缩包密码", text: $passwordInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                            if draft.passwordRequired {
                                Chip(text: "该压缩包已加密", tint: Color.orange)
                            }
                        }
                    }

                    FormSection(title: "完成后") {
                        Toggle("在 Finder 中显示解压结果", isOn: $draft.openAfterExtract)
                            .toggleStyle(.checkbox)
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

                Button("开始解压") {
                    var finalDraft = draft
                    finalDraft.password = passwordInput
                    finalDraft.policy = effectivePolicy
                    dismiss()
                    state.startExtract(finalDraft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 520)
        .background(Theme.windowBackground)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择解压目标文件夹"
        panel.prompt = "选择"
        panel.directoryURL = draft.destination

        if panel.runModal() == .OK, let url = panel.url {
            draft.destination = url
        }
    }
}
