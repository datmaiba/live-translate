import MediaPlayer

/// Lock-screen card + AirPods / headset controls.
/// Play/Pause toggles listening, Next/Previous swaps the translation direction.
final class NowPlayingController {
    private var isConfigured = false

    func configure(onToggle: @escaping () -> Void, onSwap: @escaping () -> Void) {
        guard !isConfigured else { return }
        isConfigured = true
        let center = MPRemoteCommandCenter.shared()
        let toggle: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { _ in
            DispatchQueue.main.async(execute: onToggle)
            return .success
        }
        let swap: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { _ in
            DispatchQueue.main.async(execute: onSwap)
            return .success
        }
        center.togglePlayPauseCommand.addTarget(handler: toggle)
        center.playCommand.addTarget(handler: toggle)
        center.pauseCommand.addTarget(handler: toggle)
        center.nextTrackCommand.addTarget(handler: swap)
        center.previousTrackCommand.addTarget(handler: swap)
    }

    func update(title: String, subtitle: String, isListening: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: "Live Dịch",
            MPNowPlayingInfoPropertyPlaybackRate: isListening ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
