package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.getcapacitor.JSObject;
import com.getcapacitor.plugin.util.HttpRequestHandler;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

// AudioMetadata polls the soundz-good /metadata endpoint and exposes the
// most recent track payload to AudioSource (for OS now-playing display) and
// the host service (for OS button enable/disable). The payload shape mirrors
// the soundz-backend Broadcasts\CurrentTrack WebSocket message — same field
// names, same nesting — so the in-app UI can route polling and WS through
// one handler. This polling is internal to the plugin: nothing is pushed to
// JS. The app reads the latest snapshot via AudioPlayerPlugin.getMetadata
// when it foregrounds.
public class AudioMetadata {

    private static final String TAG = "AudioMetadata";

    public String channelId = "";
    public String trackId = "";
    public String artist = "";
    public String title = "";
    public String album = "";
    // Default to the bundled favicon as the lockscreen artwork until the
    // first /metadata poll lands a real image_url. Lets us see whether
    // the "play-glyph in a circle" the OS shows is in fact the
    // MediaMetadata artwork (it should swap for the favicon here) or a
    // separate framework icon we haven't reached yet.
    public String imageUrl = "favicon.png";
    public String link = "";
    public boolean maySkip = true;

    public String updateUrl;
    public Integer updateInterval = 15;

    private Handler updateHandler = null;
    private Runnable updateRunner = null;
    private Runnable updateCallback = null;

    private AudioPlayerPlugin pluginOwner;

    AudioMetadata(String updateUrl, Integer updateInterval) {
        this.updateUrl = updateUrl;

        if (updateInterval != null) {
            this.updateInterval = updateInterval;
        }
    }

    public AudioMetadata setPluginOwner(AudioPlayerPlugin plugin) {
        pluginOwner = plugin;

        return this;
    }

    public AudioMetadata setUpdateCallBack(Runnable callback) {
        updateCallback = callback;

        return this;
    }

    public void startUpdater() {
        if (!hasUpdateUrl() || updateHandler != null) {
            return;
        }

        updateHandler = new Handler(Looper.getMainLooper());
        updateRunner = new Runnable() {
            @Override
            public void run() {
                updateMetadataByUrl(() -> updateHandler.postDelayed(this, updateInterval * 1000));
            }
        };

        // 1s delay lets the stream warm up server-side (first handleGroupStart
        // runs and populates Redis) before the first poll, so the lockscreen
        // picks up real track metadata on the very first request.
        updateHandler.postDelayed(updateRunner, 1000);
    }

    public void stopUpdater() {
        if (updateHandler == null) {
            return;
        }

        updateHandler.removeCallbacks(updateRunner);
        updateHandler = null;
        updateRunner = null;

        // One delayed final poll so the OS audio controls catch up to the
        // server's post-disconnect state (e.g. soundz-good returning channel
        // metadata after the stream connection closes and Deregister fires).
        // Without this, the lockscreen retains the last in-stream track.
        if (hasUpdateUrl()) {
            new Handler(Looper.getMainLooper()).postDelayed(
                () -> updateMetadataByUrl(null),
                1000
            );
        }
    }

    public boolean hasUpdateUrl() {
        return updateUrl != null && !updateUrl.isEmpty();
    }

    public void updateMetadataByUrl(Runnable requeueCallback) {
        if (pluginOwner.executorService.isShutdown()) {
            return;
        }

        pluginOwner.executorService.submit(() -> {
            Log.i(TAG, "poll firing for URL=" + updateUrl);
            try {
                if (makeUpdateRequest()) {
                    if (updateCallback != null) {
                        // Updating the MediaController needs to be on the main thread
                        new Handler(Looper.getMainLooper()).post(() -> {
                            updateCallback.run();
                        });
                    }
                }
            } catch (Exception ex) {
                Log.e(TAG, "There was an error running the metadata update", ex);
            } finally {
                // Always requeue — a single failed poll (e.g. 404 during stream
                // startup race) must not kill the poller permanently.
                if (requeueCallback != null) {
                    requeueCallback.run();
                }
            }
        });
    }

    private boolean makeUpdateRequest() {
        Log.i(TAG, "Getting metadata from URL " + updateUrl);
        HttpURLConnection urlConnection = null;

        try {
            URL url = new URL(updateUrl);
            urlConnection = (HttpURLConnection) url.openConnection();
            urlConnection.setRequestProperty("Accept", "application/json");

            InputStream errorStream = urlConnection.getErrorStream();

            if (errorStream != null) {
                Log.e(
                    TAG,
                    String.format(
                        "The metadata update server returned a status of %s with the message %s",
                        urlConnection.getResponseCode(),
                        HttpRequestHandler.readStreamAsString(errorStream)
                    )
                );
            } else {
                JSObject json = new JSObject(
                    HttpRequestHandler.readStreamAsString(urlConnection.getInputStream())
                );

                Log.i(TAG, json.toString());

                channelId = stringOrEmpty(json.getString("channel_id"));
                JSObject track = json.getJSObject("track");
                if (track != null) {
                    trackId = stringOrEmpty(track.getString("id"));
                    artist = stringOrEmpty(track.getString("artist"));
                    title = stringOrEmpty(track.getString("title"));
                    album = stringOrEmpty(track.getString("album"));
                    imageUrl = stringOrEmpty(track.getString("image_url"));
                    link = stringOrEmpty(track.getString("link"));
                    Boolean ms = track.getBool("may_skip");
                    maySkip = ms == null ? true : ms;
                }

                return true;
            }
        } catch (Exception ex) {
            Log.e(TAG, "An error occurred trying to get updated metadata", ex);
        } finally {
            if (urlConnection != null) {
                urlConnection.disconnect();
            }
        }

        return false;
    }

    private static String stringOrEmpty(String s) {
        return s == null ? "" : s;
    }
}
