import AVFoundation
import Capacitor
import MediaPlayer

public class AudioSource: NSObject, AVAudioPlayerDelegate {
    static let actionThumbsUp = "thumbs-up"
    static let actionThumbsDown = "thumbs-down"
    static let actionSkip = "skip"

    var id: String
    var source: String
    var streamBaseUrl: String
    var audioMetadata: AudioMetadata
    var useForNotification: Bool
    var isBackgroundMusic: Bool

    var onPlaybackStatusChangeCallbackId: String = ""
    var onReadyCallbackId: String = ""
    var onEndCallbackId: String = ""

    private var pluginOwner: AudioPlayerPlugin
    @objc private var playerItem: AVPlayerItem!
    private var player: AVPlayer!
    @objc private var playerQueue: AVQueuePlayer!
    private var playerLooper: AVPlayerLooper!
    private var nowPlayingArtwork: MPMediaItemArtwork?

    private var loopAudio: Bool
    private var isPaused: Bool = false
    private var showSeekBackward: Bool
    private var showSeekForward: Bool
    private var seekBackwardTime: Int
    private var seekForwardTime: Int

    private var audioReadyObservation: NSKeyValueObservation?
    private var audioOnEndObservation: NSObjectProtocol?

    public init(
        pluginOwner: AudioPlayerPlugin,
        id: String,
        source: String,
        streamBaseUrl: String,
        audioMetadata: AudioMetadata,
        useForNotification: Bool,
        isBackgroundMusic: Bool,
        loopAudio: Bool,
        showSeekBackward: Bool,
        showSeekForward: Bool,
        seekBackwardTime: Int,
        seekForwardTime: Int
    ) {
        self.pluginOwner = pluginOwner
        self.id = id
        self.source = source
        self.streamBaseUrl = streamBaseUrl
        self.audioMetadata = audioMetadata
        self.useForNotification = useForNotification
        self.isBackgroundMusic = isBackgroundMusic
        self.loopAudio = loopAudio
        self.showSeekBackward = showSeekBackward
        self.showSeekForward = showSeekForward
        self.seekBackwardTime = seekBackwardTime
        self.seekForwardTime = seekForwardTime

        super.init()

        self.audioMetadata.setPluginOwner(pluginOwner: pluginOwner).setUpdateCallback(
            callback: self.onMetadataUpdated
        )
    }

    func initialize() throws {
        isPaused = false
        playerItem = try createPlayerItem()

        if loopAudio {
            playerQueue = AVQueuePlayer()
            playerLooper = AVPlayerLooper.init(
                player: playerQueue,
                templateItem: playerItem
            )
            observeAudioReady()
        } else {
            observeAudioReady()
            player = AVPlayer.init(playerItem: playerItem)

            setupInterruptionNotifications()
        }
    }

    func changeAudioSource(newSource: String) throws {
        audioReadyObservation?.invalidate()
        audioReadyObservation = nil

        removeOnEndObservation()

        source = newSource
        playerItem = try createPlayerItem()

        if loopAudio {
            playerQueue.removeAllItems()
            playerLooper = AVPlayerLooper.init(
                player: playerQueue,
                templateItem: playerItem
            )
            observeAudioReady()
        } else {
            observeAudioReady()
            player.replaceCurrentItem(with: playerItem)
        }
    }

    func getDuration() -> TimeInterval {
        if loopAudio {
            return -1
        }

        if player.currentItem?.duration == CMTime.indefinite {
            return -1
        }

        return player.currentItem?.duration.seconds ?? -1
    }

    func getCurrentTime() -> TimeInterval {
        if loopAudio {
            return -1
        }

        return player.currentTime().seconds
    }

    func play() {
        // If stop() released the player item (live-radio case — the stream
        // connection must actually close so the next play starts from the
        // current broadcast time, not from stale buffered audio), rebuild
        // the player item before resuming.
        if !loopAudio && player.currentItem == nil {
            do {
                playerItem = try createPlayerItem()
                observeAudioReady()
                player.replaceCurrentItem(with: playerItem)
            } catch {
                print("Error rebuilding player item: \(error)")
                return
            }
        }

        if loopAudio {
            playerQueue.play()
        } else {
            player.play()
        }

        if !isPaused {
            setupNowPlaying()
            setupRemoteTransportControls()
        } else {
            setNowPlayingCurrentTime()
        }

        isPaused = false
        setNowPlayingPlaybackState(state: .playing)

        if useForNotification {
            audioMetadata.startUpdater()
            let cc = MPRemoteCommandCenter.shared()
            cc.likeCommand.isEnabled = true
            cc.dislikeCommand.isEnabled = true
            cc.nextTrackCommand.isEnabled = audioMetadata.maySkip
        }
    }

    func pause() {
        if loopAudio {
            playerQueue.pause()
        } else {
            player.pause()
        }

        isPaused = true
        setNowPlayingPlaybackState(state: .paused)
        audioMetadata.stopUpdater()

        if useForNotification {
            let cc = MPRemoteCommandCenter.shared()
            cc.likeCommand.isEnabled = false
            cc.dislikeCommand.isEnabled = false
            cc.nextTrackCommand.isEnabled = false
        }
    }

    func seek(timeInSeconds: Int64, fromUi: Bool = false) {
        if loopAudio {
            return
        }

        player.seek(to: getCmTime(seconds: timeInSeconds))

        if fromUi {
            removeRemoteTransportControls()
            removeNowPlaying()

            setupNowPlaying()
            setupRemoteTransportControls()
        } else {
            setNowPlayingCurrentTime()
        }
    }

    func stop() {
        if loopAudio {
            playerQueue.pause()
            playerQueue.seek(to: getCmTime(seconds: 0))
            isPaused = false
        } else {
            // Release the player item so the network connection actually
            // closes. For live radio, the next play() rebuilds the item and
            // restarts the stream at the current broadcast position rather
            // than resuming from buffered audio. Now Playing info and remote
            // transport commands stay registered so the lockscreen/Control
            // Center controls remain visible.
            player.pause()
            player.replaceCurrentItem(with: nil)
            audioReadyObservation?.invalidate()
            audioReadyObservation = nil
            removeOnEndObservation()
            isPaused = true
        }

        setNowPlayingPlaybackState(state: .paused)
        audioMetadata.stopUpdater()

        if useForNotification {
            let cc = MPRemoteCommandCenter.shared()
            cc.likeCommand.isEnabled = false
            cc.dislikeCommand.isEnabled = false
            cc.nextTrackCommand.isEnabled = false
        }
    }

    func setVolume(volume: Float) {
        if loopAudio {
            playerQueue.volume = volume
        } else {
            player.volume = volume
        }
    }

    func setRate(rate: Float) {
        if loopAudio {
            return
        }

        player.rate = rate
    }

    func setOnReady(callbackId: String) {
        onReadyCallbackId = callbackId
    }

    func setOnEnd(callbackId: String) {
        onEndCallbackId = callbackId
    }

    func setOnPlaybackStatusChange(callbackId: String) {
        onPlaybackStatusChangeCallbackId = callbackId
    }

    func getMetadata() -> [String: Any] {
        return [
            "channel_id": audioMetadata.channelId,
            "track": [
                "id": audioMetadata.trackId,
                "artist": audioMetadata.artist,
                "title": audioMetadata.title,
                "album": audioMetadata.album,
                "image_url": audioMetadata.imageUrl,
                "link": audioMetadata.link,
                "may_skip": audioMetadata.maySkip
            ] as [String: Any]
        ]
    }

    func isPlaying() -> Bool {
        if loopAudio {
            return playerQueue.rate > 0
                || playerQueue.timeControlStatus
                == AVPlayer.TimeControlStatus.playing
                || playerQueue.timeControlStatus
                == AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate
        }

        return player.rate > 0
            || player.timeControlStatus == AVPlayer.TimeControlStatus.playing
            || player.timeControlStatus
            == AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate
    }

    func destroy() {
        audioMetadata.stopUpdater()
        removeOnEndObservation()
        isPaused = false
        removeRemoteTransportControls()
        removeNowPlaying()
        removeInterruptionNotifications()
    }

    private func createPlayerItem() throws -> AVPlayerItem {
        let url = URL.init(string: source)

        if url == nil {
            throw AudioPlayerError.invalidPath
        }

        let player = AVPlayerItem.init(url: url.unsafelyUnwrapped)

        return player
    }

    private func setupInterruptionNotifications() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func removeInterruptionNotifications() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey]
                as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        if type == .began {
            print("Audio interruption has begun")
            pause()

            makePluginCall(
                callbackId: onPlaybackStatusChangeCallbackId,
                data: [
                    "status": "paused"
                ]
            )
        }

        if type == .ended {
            print("Audio interruption has ended")
            play()

            makePluginCall(
                callbackId: onPlaybackStatusChangeCallbackId,
                data: [
                    "status": "playing"
                ]
            )
        }
    }

    private func observeAudioReady() {
        if onReadyCallbackId == "" {
            return
        }

        if loopAudio {
            audioReadyObservation = observe(
                \.playerQueue?.currentItem?.status
            ) { _, _ in
                if self.playerQueue.currentItem?.status
                    == AVPlayerItem.Status.readyToPlay {
                    self.makePluginCall(callbackId: self.onReadyCallbackId)
                    self.observeOnEnd()
                }
            }
        } else {
            audioReadyObservation = observe(
                \.playerItem?.status
            ) { _, _ in
                if self.playerItem.status == AVPlayerItem.Status.readyToPlay {
                    self.makePluginCall(callbackId: self.onReadyCallbackId)
                    self.observeOnEnd()
                }
            }
        }
    }

    private func observeOnEnd() {
        if loopAudio {
            return
        }

        if player.currentItem?.duration == CMTime.indefinite {
            return
        }

        removeOnEndObservation()

        audioOnEndObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) {
            [weak self] _ in
            guard let self else { return }

            self.stop()
            self.audioMetadata.stopUpdater()

            self.makePluginCall(callbackId: self.onEndCallbackId)
        }
    }

    private func removeOnEndObservation() {
        guard let observer = audioOnEndObservation else { return }

        NotificationCenter.default.removeObserver(observer)
        audioOnEndObservation = nil
    }

    private func setupRemoteTransportControls() {
        if !useForNotification {
            return
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            if !self.isPlaying() {
                self.play()

                self.makePluginCall(
                    callbackId: self.onPlaybackStatusChangeCallbackId,
                    data: [
                        "status": "playing"
                    ]
                )

                return .success
            }

            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            print("Pause rate: " + String(self.player.rate))

            if self.isPlaying() {
                // stop() (not pause()) so the stream connection closes and
                // the next play restarts from the current broadcast time.
                self.stop()

                self.makePluginCall(
                    callbackId: self.onPlaybackStatusChangeCallbackId,
                    data: [
                        "status": "paused"
                    ]
                )

                return .success
            }

            return .commandFailed
        }

        if showSeekBackward {
            commandCenter.skipBackwardCommand.addTarget {
                [unowned self] _ -> MPRemoteCommandHandlerStatus in
                var seekTime = floor(
                    self.getCurrentTime()
                        - Double(self.seekBackwardTime)
                )

                if seekTime < 0 {
                    seekTime = 0
                }

                self.seek(timeInSeconds: Int64(seekTime))

                return .success
            }

            commandCenter.skipBackwardCommand.preferredIntervals = [
                NSNumber.init(value: self.seekBackwardTime)
            ]
        }

        if showSeekForward {
            commandCenter.skipForwardCommand.addTarget {
                [unowned self] _ -> MPRemoteCommandHandlerStatus in
                var seekTime = ceil(
                    self.getCurrentTime()
                        + Double(self.seekForwardTime)
                )
                var duration = floor(self.getDuration())

                duration = duration < 0 ? 0 : duration

                if seekTime > duration {
                    seekTime = duration
                }

                self.seek(timeInSeconds: Int64(seekTime))

                return .success
            }

            commandCenter.skipForwardCommand.preferredIntervals = [
                NSNumber.init(value: self.seekForwardTime)
            ]
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = showSeekBackward
        commandCenter.skipForwardCommand.isEnabled = showSeekForward
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false

        // likeCommand and dislikeCommand are visible only on CarPlay and
        // Apple Watch — iPhone Lock Screen and Control Center do not render
        // feedback buttons. nextTrackCommand is visible everywhere; we map
        // it to "skip current track" which mirrors Player.vue's skip button.
        commandCenter.likeCommand.localizedTitle = "Like"
        commandCenter.likeCommand.isActive = false
        commandCenter.likeCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            self.performAction(action: AudioSource.actionThumbsUp)
            return .success
        }

        commandCenter.dislikeCommand.localizedTitle = "Dislike"
        commandCenter.dislikeCommand.isActive = false
        commandCenter.dislikeCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            self.performAction(action: AudioSource.actionThumbsDown)
            return .success
        }

        commandCenter.nextTrackCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            self.performAction(action: AudioSource.actionSkip)
            return .success
        }

        commandCenter.likeCommand.isEnabled = isPlaying()
        commandCenter.dislikeCommand.isEnabled = isPlaying()
        commandCenter.nextTrackCommand.isEnabled = isPlaying() && audioMetadata.maySkip
    }

    private func removeRemoteTransportControls() {
        if !useForNotification {
            return
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.likeCommand.removeTarget(nil)
        commandCenter.dislikeCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
    }

    // performAction POSTs the listener's button press to soundz-good. On a
    // successful skip — or downvote of a may-skip track — the player
    // replaces its current item to flush buffered audio and reconnect to
    // the new playlist position, mirroring Player.vue's pause/play wrap.
    private func performAction(action: String) {
        if streamBaseUrl.isEmpty {
            print("performAction: no streamBaseUrl, dropping \(action)")
            return
        }
        let trackId = audioMetadata.trackId
        if trackId.isEmpty {
            print("performAction: no current trackId, dropping \(action)")
            return
        }

        let flushAfter = action == AudioSource.actionSkip ||
            (action == AudioSource.actionThumbsDown && audioMetadata.maySkip)

        var suffix: String
        var bodyData: Data?
        switch action {
        case AudioSource.actionSkip:
            suffix = "/skip/\(trackId)"
            bodyData = nil
        case AudioSource.actionThumbsUp:
            suffix = "/vote/\(trackId)"
            bodyData = try? JSONSerialization.data(withJSONObject: ["value": "up"])
        case AudioSource.actionThumbsDown:
            suffix = "/vote/\(trackId)"
            bodyData = try? JSONSerialization.data(withJSONObject: ["value": "down"])
        default:
            return
        }

        guard let url = URL(string: streamBaseUrl + suffix) else {
            print("performAction: invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let bodyData = bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("performAction \(action) failed: \(error)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("performAction \(action) -> non-2xx")
                return
            }
            // Re-check on the main thread before flushing: if the user
            // paused while the URLSession request was in flight,
            // flushAndReplay would force playback to resume against their
            // intent. The vote/skip itself is already recorded server-side;
            // the next user-initiated play() picks up the new playlist
            // position fresh anyway since stop() released the stream.
            if flushAfter {
                DispatchQueue.main.async {
                    if self.isPlaying() {
                        self.flushAndReplay()
                    }
                }
            }
        }.resume()
    }

    // flushAndReplay drops the buffered audio item and reconnects to /stream
    // so the listener hears the new playlist position right after a skip or
    // downvote-with-may_skip. stop() releases the player item; play() rebuilds
    // and reconnects.
    //
    // Known: AudioMetadata.stopUpdater schedules a 1s delayed final poll
    // before play()'s startUpdater fires its first request. The delayed
    // poll mutates fields concurrently with the new poller, leaving a
    // brief window of stale "between tracks" metadata on the lockscreen
    // right after a flush. Acceptable because the next regular poll
    // overwrites within ~10s; a real fix would cancel the delayed poll
    // when the updater restarts.
    private func flushAndReplay() {
        if loopAudio {
            return
        }
        stop()
        isPaused = false
        play()
    }

    private func onMetadataUpdated() {
        nowPlayingArtwork = nil

        setupNowPlaying()

        if useForNotification {
            MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = isPlaying() && audioMetadata.maySkip
        }
    }

    private func setupNowPlaying() {
        if !useForNotification {
            return
        }

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()

        nowPlayingInfo[MPMediaItemPropertyArtist] = audioMetadata.artist
        nowPlayingInfo[MPMediaItemPropertyTitle] = audioMetadata.title
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = audioMetadata.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = getDuration()
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
            getCurrentTime()
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate

        let artwork = getNowPlayingArtwork()

        if artwork != nil {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }

    private func setNowPlayingInfoKey(for key: String, value: Any?) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo

        if nowPlayingInfo == nil {
            return
        }

        nowPlayingInfo![key] = value

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func getNowPlayingArtwork() -> MPMediaItemArtwork? {
        if nowPlayingArtwork != nil {
            return nowPlayingArtwork
        }

        if !audioMetadata.imageUrl.isEmpty {
            downloadNowPlayingIcon()
        } else {
            if let image = UIImage(named: "NowPlayingIcon") {
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) {
                    _ in
                    return image
                }
            }
        }

        return nowPlayingArtwork
    }

    private func downloadNowPlayingIcon() {
        guard
            var artworkSourceUrl = URL.init(string: audioMetadata.imageUrl)
        else {
            print(
                "Error: imageUrl '" + audioMetadata.imageUrl
                    + "' is invalid (1)"
            )
            return
        }

        if artworkSourceUrl.scheme != "https" {
            guard
                let baseAppPath = pluginOwner.bridge?.config.appLocation
                    .absoluteString,
                let baseAppPathUrl = URL.init(string: baseAppPath)
            else {
                print("Error: Cannot find base path of application")
                return
            }

            artworkSourceUrl = baseAppPathUrl.appendingPathComponent(
                artworkSourceUrl.absoluteString
            )
        }

        URLSession.shared.dataTask(
            with: artworkSourceUrl
        ) { data, _, _ in
            guard let imageData = data, let image = UIImage(data: imageData)
            else {
                print(
                    "Error: artworkSource data is invalid - "
                        + artworkSourceUrl.absoluteString
                )
                return
            }

            DispatchQueue.main.async {
                self.nowPlayingArtwork = MPMediaItemArtwork(
                    boundsSize: image.size
                ) { _ in image }
                self.setNowPlayingInfoKey(
                    for: MPMediaItemPropertyArtwork,
                    value: self.nowPlayingArtwork
                )
            }
        }.resume()
    }

    private func setNowPlayingCurrentTime() {
        if !useForNotification {
            return
        }

        setNowPlayingInfoKey(
            for: MPNowPlayingInfoPropertyElapsedPlaybackTime,
            value: getCurrentTime()
        )
    }

    private func removeNowPlaying() {
        if !useForNotification {
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setNowPlayingPlaybackState(state: MPNowPlayingPlaybackState) {
        if !useForNotification {
            return
        }

        MPNowPlayingInfoCenter.default().playbackState = state
    }

    private func getCmTime(seconds: Int64) -> CMTime {
        return CMTimeMake(value: seconds, timescale: 1)
    }

    private func makePluginCall(callbackId: String) {
        makePluginCall(callbackId: callbackId, data: [:])
    }

    private func makePluginCall(callbackId: String, data: PluginCallResultData) {
        if callbackId == "" {
            return
        }

        let call = pluginOwner.bridge?.savedCall(withID: callbackId)

        if data.isEmpty {
            call?.resolve()
        } else {
            call?.resolve(data)
        }
    }
}
