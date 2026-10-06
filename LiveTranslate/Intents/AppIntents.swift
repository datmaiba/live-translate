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

struct RepeatLastIntent: AppIntent {
    static var title: LocalizedStringResource = "Đọc lại câu dịch"
    static var description = IntentDescription("Phát lại câu dịch gần nhất.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveTranslator.shared.repeatLast()
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
            intent: RepeatLastIntent(),
            phrases: ["Đọc lại \(.applicationName)", "Repeat \(.applicationName)"],
            shortTitle: "Đọc lại câu dịch",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: StartTranslatingIntent(),
            phrases: ["Bắt đầu \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Mở và bắt đầu",
            systemImageName: "mic.fill"
        )
    }
}
