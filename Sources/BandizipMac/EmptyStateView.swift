//
//  EmptyStateView.swift
//  BandizipMac
//

import SwiftUI
import ArchiveKit

struct EmptyStateView: View {
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                        .frame(width: 88, height: 88)
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Theme.accent)
                }

                VStack(spacing: 6) {
                    Text("把文件拖到这里")
                        .font(.system(size: 19, weight: .semibold))
                    Text("压缩包会直接打开预览，普通文件会立刻进入压缩流程")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button {
                        state.promptOpen()
                    } label: {
                        Label("打开压缩包", systemImage: "folder")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        state.promptNewArchive()
                    } label: {
                        Label("新建压缩包", systemImage: "plus")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        hovering ? Theme.accent.opacity(0.6) : Theme.separator,
                        style: StrokeStyle(lineWidth: hovering ? 2 : 1, dash: [7, 6])
                    )
            )
            .onHover { hovering = $0 }

            Spacer(minLength: 20)

            HStack(spacing: 6) {
                Text("支持")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                ForEach(availableFormatNames, id: \.self) { name in
                    Chip(text: name, tint: Theme.secondaryText)
                }
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.contentBackground)
    }

    private var availableFormatNames: [String] {
        state.availableFormats.map { $0.displayName }
    }
}
