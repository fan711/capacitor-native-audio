import AVFAudio
import AVKit
import Capacitor
import Foundation
import UserNotifications
import UIKit

@objc(AudioPlayerPlugin)
public class AudioPlayerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AudioPlayerPlugin"
    public let jsName = "AudioPlayer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "create", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "changeAudioSource", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateMetadata", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDuration", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentTime", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isPlaying", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getMetadata", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openOutputPicker", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "onAppGainsFocus", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAppLosesFocus", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAudioReady", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAudioEnd", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onPlaybackStatusChange", returnType: CAPPluginReturnCallback)
    ]

    let audioSession = AVAudioSession.sharedInstance()
    var audioSources = AudioSources()
    var onGainsFocusCallbackIds: [String: String] = [:]
    var onLosesFocusCallbackIds: [String: String] = [:]

    override public func load() {
        super.load()

        do {
            try audioSession.setCategory(
                AVAudioSession.Category.playback,
                mode: AVAudioSession.Mode.spokenAudio
            )

            try audioSession.setActive(false)
        } catch {
            print("Failed to set audio session category")
        }

        print("Listening to app background/foreground event changes")

        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppToBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppToForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Ad-indicator notifications. The authorisation request fires from
        // create() when useForNotification=true so the OS prompt shows up at
        // a moment the user has context for (just tapped play) rather than
        // at WebView startup. Setting the delegate here ensures foreground
        // / tap callbacks are wired from the start.
        UNUserNotificationCenter.current().delegate = self
    }

    @objc func create(_ call: CAPPluginCall) {
        do {
            let sourceId = try audioId(call)

            if audioSources.exists(sourceId: sourceId) {
                print("An audio source with the ID \(sourceId) already exists")
                call.reject("There was an issue creating the audio player [0].")

                return
            }

            guard let streamBaseUrl = call.getString("streamBaseUrl"),
                  !streamBaseUrl.isEmpty
            else {
                throw AudioPlayerError.invalidPath
            }

            let audioSource = AudioSource(
                pluginOwner: self,
                id: sourceId,
                source: streamBaseUrl + "/stream",
                streamBaseUrl: streamBaseUrl,
                audioMetadata: AudioMetadata(
                    updateUrl: streamBaseUrl + "/metadata-upcoming"
                ),
                useForNotification: call.getBool("useForNotification", false),
                isBackgroundMusic: call.getBool("isBackgroundMusic", false),
                loopAudio: call.getBool("loop", false),
                showSeekBackward: call.getBool("showSeekBackward", true),
                showSeekForward: call.getBool("showSeekForward", true),
                seekBackwardTime: call.getInt("seekBackwardTime", 5),
                seekForwardTime: call.getInt("seekForwardTime", 5)
            )

            if audioSources.count() == 0 && !audioSource.useForNotification {
                throw AudioPlayerError.runtimeError(
                    "An audio source with useForNotification = true must exist first."
                )
            }

            if audioSources.hasNotification() && audioSource.useForNotification {
                throw AudioPlayerError.runtimeError(
                    "An audio source with useForNotification = true already exists. There can only be one."
                )
            }

            try audioSources.add(source: audioSource)

            if audioSource.useForNotification {
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { granted, _ in
                    if !granted {
                        print("Ad-indicator notification permission not granted")
                    }
                }
            }

            call.resolve()
        } catch {
            call.reject(
                "There was an issue creating the audio player [1].",
                nil,
                error
            )
        }
    }

    @objc func initialize(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "initialize", call: call)
                .initialize()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing the audio player.",
                nil,
                error
            )
        }
    }

    @objc func changeAudioSource(_ call: CAPPluginCall) {
        do {
            guard let newSource = call.getString("source") else {
                throw AudioPlayerError.invalidSource
            }

            try getAudioSource(methodName: "changeAudioSource", call: call)
                .changeAudioSource(newSource: newSource)

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue changing the audio source.",
                nil,
                error
            )
        }
    }

    @objc func updateMetadata(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "updateMetadata", call: call)
                .audioMetadata
                .updateMetadataByUrl()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue updating the metadata.",
                nil,
                error
            )
        }
    }

    @objc func getDuration(_ call: CAPPluginCall) {
        do {
            let duration = try getAudioSource(
                methodName: "duration",
                call: call
            ).getDuration()

            call.resolve(["duration": duration])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the duration for the audio source.",
                nil,
                error
            )
        }
    }

    @objc func getCurrentTime(_ call: CAPPluginCall) {
        do {
            let currentTime = try getAudioSource(
                methodName: "currentTime",
                call: call
            ).getCurrentTime()

            call.resolve(["currentTime": currentTime])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the current time for the audio source.",
                nil,
                error
            )
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        do {
            let audioSource = try getAudioSource(methodName: "play", call: call)

            if audioSource.useForNotification {
                try audioSession.setActive(true)
            }

            audioSource.play()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue playing the audio.", nil, error)
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "pause", call: call).pause()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue pausing the audio.", nil, error)
        }
    }

    @objc func seek(_ call: CAPPluginCall) {
        do {
            guard let timeInSeconds = call.getInt("timeInSeconds") else {
                throw AudioPlayerError.invalidSeekTime
            }

            try getAudioSource(methodName: "seek", call: call).seek(
                timeInSeconds: Int64(timeInSeconds),
                fromUi: true
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue seeking the audio.", nil, error)
        }
    }

    /// Stub for the on-demand episode timeline. JS passes the full playlist
    /// + per-item display metadata so Control Center can be driven from local
    /// audio position instead of HTTP polling. Resolves immediately — the
    /// nowPlayingInfo-driving implementation is a follow-up; ignoring here
    /// is safe because the app-side metadata still drives the in-app UI.
    @objc func setEpisodeTimeline(_ call: CAPPluginCall) {
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        do {
            let audioSource = try getAudioSource(methodName: "stop", call: call)

            audioSource.stop()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue stopping the audio.", nil, error)
        }
    }

    @objc func setVolume(_ call: CAPPluginCall) {
        do {
            guard let volume = call.getFloat("volume") else {
                throw AudioPlayerError.invalidSeekTime
            }

            try getAudioSource(methodName: "setVolume", call: call).setVolume(
                volume: volume
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue setting the audio volume.",
                nil,
                error
            )
        }
    }

    @objc func setRate(_ call: CAPPluginCall) {
        do {
            guard let rate = call.getFloat("rate") else {
                throw AudioPlayerError.invalidRate
            }

            try getAudioSource(methodName: "setRate", call: call).setRate(
                rate: rate
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue setting the rate of the audio.",
                nil,
                error
            )
        }
    }

    @objc func isPlaying(_ call: CAPPluginCall) {
        do {
            let isPlaying = try getAudioSource(
                methodName: "isPlaying",
                call: call
            ).isPlaying()

            call.resolve(["isPlaying": isPlaying])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the playing status of the audio.",
                nil,
                error
            )
        }
    }

    @objc func getMetadata(_ call: CAPPluginCall) {
        do {
            let metadata = try getAudioSource(
                methodName: "getMetadata",
                call: call
            ).getMetadata()

            call.resolve(metadata)
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the metadata.",
                nil,
                error
            )
        }
    }

    @objc func destroy(_ call: CAPPluginCall) {
        do {
            let audioSource = try getAudioSource(
                methodName: "destroy",
                call: call
            )

            if audioSource.useForNotification {
                try audioSession.setActive(false)
            }

            audioSource.stop()
            audioSource.destroy()

            let audioId = try audioId(call)

            audioSources.remove(sourceId: audioId)
            onLosesFocusCallbackIds.removeValue(forKey: audioId)
            onGainsFocusCallbackIds.removeValue(forKey: audioId)

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue cleaning up the audio player.",
                nil,
                error
            )
        }
    }

    @objc func openOutputPicker(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let hostView = self?.webView ?? self?.bridge?.viewController?.view else {
                call.reject("No host view to present the route picker.")
                return
            }

            // iOS exposes no public API to present the AirPlay picker directly,
            // so add a hidden AVRoutePickerView and trigger its internal button.
            let picker = AVRoutePickerView(frame: .zero)
            picker.isHidden = true
            hostView.addSubview(picker)

            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }

            // Remove on the next runloop tick, once UIKit has presented the
            // picker sheet anchored to this view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                picker.removeFromSuperview()
            }

            call.resolve()
        }
    }

    @objc func onAppGainsFocus(_ call: CAPPluginCall) {
        do {
            call.keepAlive = true
            bridge?.saveCall(call)

            onGainsFocusCallbackIds[try audioId(call)] = call.callbackId
        } catch {
            call.reject(
                "There was an issue registering onAppGainsFocus",
                nil,
                error
            )
        }
    }

    @objc func onAppLosesFocus(_ call: CAPPluginCall) {
        do {
            call.keepAlive = true
            bridge?.saveCall(call)

            onLosesFocusCallbackIds[try audioId(call)] = call.callbackId
        } catch {
            call.reject(
                "There was an issue registering onAppLosesFocus",
                nil,
                error
            )
        }
    }

    @objc func onAudioReady(_ call: CAPPluginCall) {
        call.keepAlive = true
        bridge?.saveCall(call)

        do {
            try getAudioSource(methodName: "onAudioReady", call: call)
                .setOnReady(callbackId: call.callbackId)
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing audio ready.",
                nil,
                error
            )
        }
    }

    @objc func onAudioEnd(_ call: CAPPluginCall) {
        call.keepAlive = true
        bridge?.saveCall(call)

        do {
            try getAudioSource(methodName: "onAudioEnd", call: call).setOnEnd(
                callbackId: call.callbackId
            )
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing audio end.",
                nil,
                error
            )
        }

    }

    @objc func onPlaybackStatusChange(_ call: CAPPluginCall) {
        call.keepAlive = true
        bridge?.saveCall(call)

        do {
            try getAudioSource(methodName: "onPlaybackStatusChange", call: call)
                .setOnPlaybackStatusChange(callbackId: call.callbackId)
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing playback status change.",
                nil,
                error
            )
        }
    }

    @objc func handleAppToBackground() {
        print("Going to background")

        makeFocusChangeCallbackCalls(callbackIds: onLosesFocusCallbackIds)
    }

    @objc func handleAppToForeground() {
        print("Coming to foreground")

        makeFocusChangeCallbackCalls(callbackIds: onGainsFocusCallbackIds)
    }

    func audioId(_ call: CAPPluginCall) throws -> String {
        guard let audioId = call.getString("audioId") else {
            throw AudioPlayerError.invalidAudioId
        }

        return audioId
    }

    func getAudioSource(methodName: String, call: CAPPluginCall) throws
    -> AudioSource {
        return try getAudioSource(
            methodName: methodName,
            call: call,
            rejectIfError: true
        )
    }

    func getAudioSource(
        methodName: String,
        call: CAPPluginCall,
        rejectIfError: Bool
    ) throws -> AudioSource {
        let audioSource = audioSources.get(sourceId: try audioId(call))

        if audioSource == nil {
            print("Audio source with ID \(try audioId(call)) was not found.")

            if rejectIfError {
                call.reject(
                    "There was an issue trying to play the audio (\(methodName))"
                )
            }

            throw AudioPlayerError.missingAudioSource
        }

        return audioSource!
    }

    func makeFocusChangeCallbackCalls(callbackIds: [String: String]) {
        for callbackId in callbackIds.values {
            bridge?.savedCall(withID: callbackId)?.resolve()
        }
    }
}

extension AudioPlayerPlugin: UNUserNotificationCenterDelegate {
    // Tap on the ad-indicator notification → open the click-tracking URL in
    // Safari. The URL is stashed in userInfo when the notification is posted
    // (see AudioMetadata.swift). Empty / missing → fall through to the OS
    // default which opens the app.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["target_url"] as? String,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        completionHandler()
    }

    // App in foreground when the notification fires — keep it shade-only,
    // never banner over our own UI. Matches Android's IMPORTANCE_LOW.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list])
    }
}
