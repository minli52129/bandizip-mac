//
//  Theme.swift
//  BandizipMac
//
//  统一的视觉组件。整体走 macOS 原生观感：浅色底 + 细边框 + 克制用色。
//

import SwiftUI

enum Theme {
    static let accent = Color(red: 0.20, green: 0.40, blue: 0.92)
    static let rowHeight: CGFloat = 25
    static let headerHeight: CGFloat = 26

    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var contentBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var barBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
}

/// 顶部工具条上的大图标按钮
struct ToolButton: View {
    let title: String
    let icon: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(height: 17)
                Text(title)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(width: 58, height: 40)
            .foregroundStyle(disabled ? Theme.tertiaryText : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering && !disabled ? Color.primary.opacity(0.07) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(title)
    }
}

/// 侧边栏分组标题
struct SidebarSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.tertiaryText)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// 侧边栏条目
struct SidebarRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var selected: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: subtitle == nil ? 24 : 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.accent : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 表头单元格
struct HeaderCell: View {
    let title: String
    var width: CGFloat? = nil
    var trailing: Bool = false
    var sortable: Bool = true
    var active: Bool = false
    var ascending: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            if trailing { Spacer(minLength: 0) }
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Theme.secondaryText)
            if active {
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if !trailing { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: Theme.headerHeight)
        .contentShape(Rectangle())
        .onTapGesture { if sortable { action?() } }
    }
}

/// 面板分组标题（压缩 / 解压对话框里用）
struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            content
        }
    }
}

/// 设置 / 弹窗标题栏
struct DialogHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String = "doc.zipper"

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// 一个小圆角标签
struct Chip: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .foregroundStyle(tint)
    }
}
