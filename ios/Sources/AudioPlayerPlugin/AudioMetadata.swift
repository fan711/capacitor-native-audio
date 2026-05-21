import Capacitor
import UserNotifications

// AudioMetadata fetches a 2-minute lookahead of upcoming track changes from
// soundz-good's /metadata-upcoming endpoint every 60 s, holds the items in
// a local queue, and applies each to the OS Now Playing display at its
// own from_us via a single self-rearming apply timer. AudioSource still
// reads the current track via the same property surface (artist, title,
// trackId, …) — those are now computed from the queue's currently-active
// entry rather than the single track payload of the old endpoint.
//
// Queue is dropped on stop/play/skip (the old timeline is stale); the
// next refresh repopulates it. Apply-timer fires also drop entries whose
// to_us is in the past, so the queue stays small.
public class AudioMetadata {
    // Silent shade-only ad-indicator notification, mirror of the Android
    // implementation. Gated on `is_ad` AND a non-empty `target_url`: the
    // backend now populates target_url for any track with a click destination
    // (ads and songs alike), so is_ad is what distinguishes "show the ad
    // shade" from a song's in-app click-through.
    private static let adNotificationId = "now_playing_passive"

    private static let refreshIntervalSeconds: Int = 60

    var channelId: String = ""
    var updateUrl: String

    private var queue: [UpcomingMetadataItem] = []
    private let queueLock = NSLock()

    private var refreshTimer: DispatchSourceTimer?
    private var applyTimer: DispatchSourceTimer?

    private var updateCallback: (() -> Void)!
    private var pluginOwner: AudioPlayerPlugin?

    private var pollerActive: Bool = false
    private var previousNotifiedTrackId: String = ""

    // Current-item accessors: AudioSource and the host plugin read these
    // identically to before; the underlying storage is now the queue.
    var trackId: String { currentItem()?.id ?? "" }
    var artist: String { currentItem()?.artist ?? "" }
    var title: String { currentItem()?.title ?? "" }
    var album: String { currentItem()?.album ?? "" }
    var imageUrl: String { currentItem()?.imageUrl ?? "" }
    var maySkip: Bool { currentItem()?.maySkip ?? true }
    var isAd: Bool { currentItem()?.isAd ?? false }
    var targetUrl: String { currentItem()?.targetUrl ?? "" }

    public init(updateUrl: String) {
        self.updateUrl = updateUrl
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
        if !hasUpdateUrl() || refreshTimer != nil {
            return
        }

        pollerActive = true
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .background)
        )
        // 1s initial delay lets the stream warm up server-side (the
        // forwarder's first items reach Redis) before the first poll, so
        // the lockscreen picks up real metadata on the very first request.
        timer.schedule(
            deadline: .now() + 1.0,
            repeating: .seconds(Self.refreshIntervalSeconds),
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            self?.makeUpdateRequest()
        }
        refreshTimer = timer
        timer.activate()
    }

    public func stopUpdater() {
        if refreshTimer == nil {
            return
        }

        pollerActive = false
        clearAdNotification()
        refreshTimer?.cancel()
        refreshTimer = nil
        applyTimer?.cancel()
        applyTimer = nil

        // Drop the queue: the next session's timeline is unrelated.
        queueLock.lock()
        queue = []
        queueLock.unlock()

        // One delayed final poll so the OS audio controls catch up to the
        // server's post-disconnect state (e.g. soundz-good returning channel
        // metadata after the stream connection closes and Deregister fires).
        if hasUpdateUrl() {
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                self.makeUpdateRequest()
            }
        }
    }

    public func hasUpdateUrl() -> Bool {
        return !updateUrl.isEmpty
    }

    // Force a one-shot refresh — same semantics as before, used by the
    // foreground-resume path on the JS side.
    public func updateMetadataByUrl() {
        makeUpdateRequest()
    }

    private func currentItem() -> UpcomingMetadataItem? {
        let nowUs = AudioMetadata.nowUs()
        queueLock.lock()
        defer { queueLock.unlock() }
        for item in queue {
            if item.fromUs <= nowUs && nowUs <= item.toUs {
                return item
            }
        }
        return nil
    }

    private static func nowUs() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    private func makeUpdateRequest() {
        guard let updateUrl = URL(string: self.updateUrl) else {
            print("Update metadata URL is invalid")
            return
        }

        var updateRequest = URLRequest(url: updateUrl)
        updateRequest.addValue("application/json", forHTTPHeaderField: "Accept")

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

                self.channelId = json["channel_id"] as? String ?? ""
                var newQueue: [UpcomingMetadataItem] = []
                if let items = json["items"] as? [[String: Any]] {
                    for item in items {
                        newQueue.append(UpcomingMetadataItem(json: item))
                    }
                }
                newQueue.sort { $0.fromUs < $1.fromUs }

                self.queueLock.lock()
                self.queue = newQueue
                self.queueLock.unlock()

                // Apply the now-active entry immediately (the refresh
                // landed mid-group; the previous queue's current item may
                // have differed) and arm the next-item timer.
                DispatchQueue.main.async {
                    self.fireMetadataUpdated()
                }
                self.scheduleNextApply()
            } catch {
                print(
                    "An error occurred trying to get updated metadata: \(error.localizedDescription)"
                )
            }
        }.resume()
    }

    // scheduleNextApply prunes outdated entries and arms a one-shot timer
    // for the next item whose from_us is in the future. The timer's fire
    // handler invokes the OS-update callback and self-rearms for the item
    // after that — so there's only ever one pending DispatchSourceTimer.
    private func scheduleNextApply() {
        applyTimer?.cancel()
        applyTimer = nil

        let nowUs = AudioMetadata.nowUs()
        queueLock.lock()
        queue = queue.filter { $0.toUs >= nowUs }
        let next = queue.first(where: { $0.fromUs > nowUs })
        queueLock.unlock()

        guard let next = next else { return }

        let delaySeconds = max(0.0, Double(next.fromUs - nowUs) / 1_000_000.0)
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .background)
        )
        timer.schedule(deadline: .now() + delaySeconds, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.fireMetadataUpdated()
            }
            self.scheduleNextApply()
        }
        applyTimer = timer
        timer.activate()
    }

    private func fireMetadataUpdated() {
        syncAdNotification()
        if updateCallback != nil {
            updateCallback()
        }
    }

    private func syncAdNotification() {
        guard pollerActive else { return }

        let center = UNUserNotificationCenter.current()

        // Same gate as Android: only show the shade notification for ads
        // with a click destination. Songs may also carry target_url but get
        // their click-through from the in-app UI, not a shade notification.
        guard isAd && !targetUrl.isEmpty else {
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

struct UpcomingMetadataItem {
    let fromUs: Int64
    let toUs: Int64
    let id: String
    let artist: String
    let title: String
    let album: String
    let imageUrl: String
    let maySkip: Bool
    let isAd: Bool
    let targetUrl: String

    init(json: [String: Any]) {
        self.fromUs = (json["from_us"] as? NSNumber)?.int64Value ?? 0
        self.toUs = (json["to_us"] as? NSNumber)?.int64Value ?? 0
        self.id = json["id"] as? String ?? ""
        self.artist = json["artist"] as? String ?? ""
        self.title = json["title"] as? String ?? ""
        self.album = json["album"] as? String ?? ""
        self.imageUrl = json["image_url"] as? String ?? ""
        self.maySkip = json["may_skip"] as? Bool ?? true
        self.isAd = json["is_ad"] as? Bool ?? false
        self.targetUrl = json["target_url"] as? String ?? ""
    }
}
