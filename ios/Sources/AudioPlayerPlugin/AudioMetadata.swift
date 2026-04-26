import Capacitor

// AudioMetadata polls the soundz-good /metadata endpoint and exposes the
// most recent track payload to AudioSource (for OS Now Playing display)
// and the host plugin (for OS button enable/disable). The payload shape
// mirrors the soundz-backend Broadcasts\CurrentTrack WebSocket message —
// same field names, same nesting — so the in-app UI can route polling and
// WS through one handler. Polling is internal to the plugin: nothing is
// pushed to JS. The app reads the latest snapshot via getMetadata when it
// foregrounds.
public class AudioMetadata {
    var channelId: String = ""
    var trackId: String = ""
    var artist: String = ""
    var title: String = ""
    var album: String = ""
    var imageUrl: String = ""
    var link: String = ""
    var maySkip: Bool = true
    var updateUrl: String
    var updateInterval: Int = 15

    private var updateHandler: DispatchSourceTimer!
    private var updateCallback: (() -> Void)!

    private var pluginOwner: AudioPlayerPlugin?

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
                }
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
}
