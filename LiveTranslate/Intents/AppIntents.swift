import AppIntents

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case needsApp

    var localizedStringResource: LocalizedStringResource {
        "Mở Live Dịch và bấm Bắt đầu một lần trước."
    }
}

/// Runs without opening the app — bind it to Back Tap for hidden use.
struct ToggleListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Bật/Tắt dịch"
    static var description = IntentDescription("Bật hoặc tạm dừng dịch trực tiếp mà không cần mở app.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let translator = LiveTranslator.shared
        if translator.state == .idle {
            await translator.start()
            if translator.state == .idle { throw IntentFailure.needsApp }
        } else {
            translator.toggle()
        }
        return .result()
    }
}

struct SwapDirectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Đổi chiều dịch"
    static var description = IntentDescription("Đổi giữa Việt → Anh và Anh → Việt.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveTranslator.shared.swapDirection()
        return .result()
    }
}

struct StartTranslatingIntent: AppIntent {
    static var title: LocalizedStringResource = "Mở và bắt đầu dịch"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveTranslator.shared.start()
        return .result()
    }
}

struct LiveTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleListeningIntent(),
            phrases: ["Bật tắt dịch \(.applicationName)", "Toggle \(.applicationName)"],
            shortTitle: "Bật/Tắt dịch",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: SwapDirectionIntent(),
            phrases: ["Đổi chiều \(.applicationName)", "Swap \(.applicationName)"],
            shortTitle: "Đổi chiều dịch",
            systemImageName: "arrow.left.arrow.right"
        )
        AppShortcut(
            intent: StartTranslatingIntent(),
            phrases: ["Bắt đầu \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Mở và bắt đầu",
            systemImageName: "mic.fill"
        )
    }
}
