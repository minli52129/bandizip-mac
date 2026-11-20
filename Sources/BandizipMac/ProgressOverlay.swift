//
//  ProgressOverlay.swift
//  BandizipMac
//

import SwiftUI

struct ProgressOverlay: View {
    @ObservedObject var state: ProgressState

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(state.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if state.isDeterminate {
                        Text("\(Int(state.fraction * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                }

                if state.isDeterminate {
                    ProgressView(value: min(max(state.fraction, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                }

                HStack(spacing: 8) {
                    Text(state.detail)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                    Text(state.speedText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }

                HStack(spacing: 8) {
                    Text(state.remainingText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer(minLength: 0)
                    Button("取消") {
                        state.cancel()
                    }
                    .controlSize(.small)
                    .disabled(state.isCancelled)
                }
            }
            .padding(18)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 10)
        }
    }
}
