import Capacitor
import UserNotifications

// AudioMetadata polls the soundz-good /metadata endpoint and exposes the
// most recent track payload to AudioSource (for OS Now Playing display)
// and the host plugin (for OS button enable/disable). The payload shape
// mirrors the soundz-backend Broadcasts\CurrentTrack WebSocket message —
// same field names, same nesting — so the in-app UI can route polling and
// WS through one handler. Polling is internal to the plugin: nothing is
// pushed to JS. The app reads the latest snapshot via getMetadata when it
// foregrounds.
public class AudioMetadata {
    // Silent shade-only ad-indicator notification, mirror of the Android
    // implementation. Gated on the metadata payload carrying a non-empty
    // `target_url`, which the backend only emits for ads with a configured
    // click destination — so the notification appearing always implies a
    // tap target.
    private static let adNotificationId = "now_playing_passive"

    var channelId: String = ""
    var trackId: String = ""
    var artist: String = ""
    var title: String = ""
    var album: String = ""
    var imageUrl: String = ""
    var link: String = ""
    var maySkip: Bool = true
    var isAd: Bool = false
    var targetUrl: String = ""
    var updateUrl: String
    var updateInterval: Int = 15

    private var updateHandler: DispatchSourceTimer!
    private var updateCallback: (() -> Void)!

    private var pluginOwner: AudioPlayerPlugin?

    private var pollerActive: Bool = false
    private var previousNotifiedTrackId: String = ""

    public init(updateUrl: String, updateInterval: Int) {
        self.updateUrl = updateUrl

        if updateInterval != -1 {
            self.updateInterval = updateInterval
        }
    }

    public func setPluginOwner(pluginOwner: AudioPlayerPlugin) -> Self {
        self.pluginOwner = pluginOwner

        return self
    }

    public func setUpdateCallback(callback: @escaping () -> Void) -> Self {
        self.updateCallback = callback

        return self
    }

    public func startUpdater() {
        if !hasUpdateUrl() || updateHandler != nil {
            return
        }

        pollerActive = true
        updateHandler = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .background)
        )
        // 1s initial delay lets the stream warm up server-side (first
        // handleGroupStart populates Redis) before the first poll, so the
        // lockscreen picks up real track metadata on the very first request.
        updateHandler.schedule(
            deadline: .now() + 1.0,
            repeating: .seconds(updateInterval),
            leeway: .milliseconds(250)
        )
        updateHandler.setEventHandler {
            self.makeUpdateRequest()
        }

        updateHandler.activate()
    }

    public func stopUpdater() {
        if updateHandler == nil {
            return
        }

        pollerActive = false
        clearAdNotification()
        updateHandler.cancel()
        updateHandler = nil

        // One delayed final poll so the OS audio controls catch up to the
        // server's post-disconnect state (e.g. soundz-good returning channel
        // metadata after the stream connection closes and Deregister fires).
        // Without this, the lockscreen retains the last in-stream track.
        if hasUpdateUrl() {
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                self.updateMetadataByUrl()
            }
        }
    }

    public func hasUpdateUrl() -> Bool {
        return !updateUrl.isEmpty
    }

    public func updateMetadataByUrl() {
        makeUpdateRequest()
    }

    private func makeUpdateRequest() {
        guard
            let updateUrl = URL.init(string: self.updateUrl)
        else {
            print("Update metadata URL is invalid")
            return
        }

        var updateRequest = URLRequest(url: updateUrl)
        updateRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        print("Getting metadata from URL \(self.updateUrl)")

        URLSession.shared.dataTask(with: updateRequest) { (data, response, error) in
            if let error = error {
                print(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("The metadata update server response is invalid")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                print(
                    "The metadata update server returned a non-2xx status code: \(httpResponse.statusCode)"
                )
                return
            }

            do {
                guard
                    let json = (try JSONSerialization.jsonObject(with: data!)) as? [String: Any]
                else {
                    print("The metadata update data could not be parsed as JSON")
                    return
                }

                print(json)

                self.channelId = json["channel_id"] as? String ?? ""
                if let track = json["track"] as? [String: Any] {
                    self.trackId = track["id"] as? String ?? ""
                    self.artist = track["artist"] as? String ?? ""
                    self.title = track["title"] as? String ?? ""
                    self.album = track["album"] as? String ?? ""
                    self.imageUrl = track["image_url"] as? String ?? ""
                    self.link = track["link"] as? String ?? ""
                    self.maySkip = track["may_skip"] as? Bool ?? true
                    self.isAd = track["is_ad"] as? Bool ?? false
                    self.targetUrl = track["target_url"] as? String ?? ""
                } else {
                    self.isAd = false
                    self.targetUrl = ""
                }

                self.syncAdNotification()
            } catch {
                print(
                    "An error occurred trying to get updated metadata: \(error.localizedDescription)"
                )
            }

            if self.updateCallback != nil {
                DispatchQueue.main.async {
                    self.updateCallback()
                }
            }
        }.resume()
    }

    private func syncAdNotification() {
        guard pollerActive else { return }

        let center = UNUserNotificationCenter.current()

        // Same gate as Android: target_url presence drives whether we show
        // the notification at all. Empty / non-ad → cancel any prior one and
        // bail.
        guard !targetUrl.isEmpty else {
            center.removeDeliveredNotifications(withIdentifiers: [Self.adNotificationId])
            center.removePendingNotificationRequests(withIdentifiers: [Self.adNotificationId])
            previousNotifiedTrackId = ""
            return
        }

        // Skip repeat polls of the same track to avoid flicker. Each
        // re-post would trigger a brief shade refresh even at .passive.
        guard trackId != previousNotifiedTrackId else { return }
        previousNotifiedTrackId = trackId

        // Capture state for the closure — the URLSession callback runs on a
        // background queue and the metadata fields could change before we
        // post.
        let snapshotTitle = title.isEmpty ? "Now playing" : title
        let snapshotArtist = artist
        let snapshotTargetUrl = targetUrl
        let snapshotImageUrl = imageUrl

        fetchAttachmentURL(snapshotImageUrl) { attachmentURL in
            let content = UNMutableNotificationContent()
            content.title = snapshotTitle
            content.body = snapshotArtist
            content.sound = nil
            content.interruptionLevel = .passive  // shade-only, no banner
            content.userInfo = ["target_url": snapshotTargetUrl]

            if let url = attachmentURL,
               let attachment = try? UNNotificationAttachment(
                   identifier: "art",
                   url: url,
                   options: nil
               ) {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: Self.adNotificationId,
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error = error {
                    print("Failed to post ad-indicator notification: \(error)")
                }
            }
        }
    }

    private func clearAdNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.adNotificationId])
        center.removePendingNotificationRequests(withIdentifiers: [Self.adNotificationId])
        previousNotifiedTrackId = ""
    }

    // UNNotificationAttachment requires a local file URL. Mirror
    // AudioSource.downloadNowPlayingIcon's URLSession pattern but write to a
    // unique tmp file so back-to-back ads don't collide. Returns nil for
    // empty/invalid URLs, network errors, or write failures — caller posts
    // the notification without an attachment. Image is optional, never fatal.
    private func fetchAttachmentURL(
        _ urlString: String,
        completion: @escaping (URL?) -> Void
    ) {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased())
        else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try data.write(to: tmp)
                completion(tmp)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
