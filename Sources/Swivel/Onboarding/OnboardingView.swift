import Combine
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case accessibility, screenRecording, view, ready

    static var firstIncomplete: OnboardingStep {
        if !Permissions.hasAccessibility {
            return .accessibility
        }
        return Permissions.hasScreenRecording ? .view : .screenRecording
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: Permissions.hasAccessibility
        case .screenRecording: Permissions.hasScreenRecording
        case .view, .ready: false
        }
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @State private var isGranted = false
    @State private var hasSwitched = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(SettingKey.showPreview) private var showPreview = false
    @AppStorage(SettingKey.theme) private var theme = ThemeChoice.glass

    private static let grantedPause: Duration = .milliseconds(900)
    private let permissionPoll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(startingAt step: OnboardingStep = .firstIncomplete, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            page
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            StepDots(current: step)
                .padding(.bottom, 24)
        }
        .frame(width: 460, height: 440)
        .onReceive(permissionPoll) { _ in
            noteIfGranted()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switcherDidOpen)) { _ in
            withAnimation(.spring(duration: 0.4)) {
                hasSwitched = true
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .accessibility:
            PermissionPage(
                symbol: "accessibility",
                title: "Allow Accessibility",
                detail: "Swivel reads window titles and listens for ⌘Tab. Nothing leaves your Mac.",
                grantLabel: "Grant Accessibility",
                isGranted: isGranted,
                grant: Permissions.requestAccessibility,
                skip: nil
            )
        case .screenRecording:
            PermissionPage(
                symbol: "macwindow.on.rectangle",
                title: "Allow Screen Recording",
                detail: "Only used to preview a window while you hold Space. macOS will ask to reopen Swivel.",
                grantLabel: "Grant Screen Recording",
                isGranted: isGranted,
                grant: Permissions.requestScreenRecording,
                skip: { advance(to: .view) }
            )
        case .view:
            viewPage
        case .ready:
            readyPage
        }
    }

    private var viewPage: some View {
        VStack(spacing: 22) {
            Text("Choose your view")
                .font(.system(size: 24, weight: .semibold))

            HStack(spacing: 14) {
                ViewCard(label: "Compact", showsPreview: false, theme: theme.theme, isSelected: !showPreview) {
                    showPreview = false
                }
                ViewCard(label: "With preview", showsPreview: true, theme: theme.theme, isSelected: showPreview) {
                    showPreview = true
                }
            }

            Picker("Theme", selection: $theme) {
                ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button("Continue") { advance(to: .ready) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .animation(.spring(duration: 0.3), value: showPreview)
        .animation(.spring(duration: 0.3), value: theme)
    }

    private var readyPage: some View {
        VStack(spacing: 22) {
            Tile(isDone: hasSwitched) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
            }

            Text(hasSwitched ? "You're set" : "Try it")
                .font(.system(size: 24, weight: .semibold))
                .contentTransition(.opacity)

            HStack(spacing: 6) {
                Keycap("⌘")
                Keycap("Tab")
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                    } catch {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }

            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 48)
    }

    private func noteIfGranted() {
        guard !isGranted, step.isGranted else {
            return
        }

        withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
            isGranted = true
        }
        Task {
            try? await Task.sleep(for: Self.grantedPause)
            advance(to: OnboardingStep(rawValue: step.rawValue + 1) ?? .ready)
        }
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.spring(duration: 0.5)) {
            step = next
            isGranted = false
        }
    }
}

private struct PermissionPage: View {
    let symbol: String
    let title: String
    let detail: String
    let grantLabel: String
    let isGranted: Bool
    let grant: () -> Void
    let skip: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Tile(isDone: isGranted) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                if isGranted {
                    Label("Granted", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(height: 30)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Button(grantLabel, action: grant)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .transition(.opacity)
                }

                if let skip {
                    Button("Skip", action: skip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .opacity(isGranted ? 0 : 1)
                }
            }
        }
        .padding(.horizontal, 48)
    }
}

/// The rounded icon square, which flips to a green tick when its step is done.
private struct Tile<Content: View>: View {
    let isDone: Bool
    @ViewBuilder let content: Content

    private static var side: CGFloat { 84 }

    var body: some View {
        ZStack {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.green.gradient)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                content
                    .transition(.opacity)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: (isDone ? Color.green : .black).opacity(0.3), radius: 14, y: 6)
        .scaleEffect(isDone ? 1.06 : 1)
    }
}

/// A selectable miniature of the switcher panel.
private struct ViewCard: View {
    let label: String
    let showsPreview: Bool
    let theme: Theme
    let isSelected: Bool
    let select: () -> Void

    private static let selectedRow = 1

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                miniature
                    .frame(width: 168, height: 104)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 1)
                    }

                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var miniature: some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.appName.opacity(0.6)).frame(width: 16, height: 4)
                        RoundedRectangle(cornerRadius: 2.5).fill(theme.text.opacity(0.8)).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 2).fill(theme.text.opacity(0.8)).frame(height: 4)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 15)
                    .background(row == Self.selectedRow ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(8)

            if showsPreview {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.text.opacity(0.22))
                    .padding(10)
                    .frame(width: 66)
                    .background(theme.previewBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }
}

private struct Keycap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal, 10)
            .frame(minWidth: 34, minHeight: 32)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
    }
}

private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: step == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(duration: 0.4), value: current)
    }
}

extension Notification.Name {
    static let switcherDidOpen = Notification.Name("switcherDidOpen")
}
