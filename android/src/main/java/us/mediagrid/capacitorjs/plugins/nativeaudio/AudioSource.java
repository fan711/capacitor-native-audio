package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.content.Context;
import android.net.Uri;
import android.os.Binder;
import android.util.Log;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import com.getcapacitor.JSObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class AudioSource extends Binder {

    public static final String ACTION_THUMBS_UP = "thumbs-up";
    public static final String ACTION_THUMBS_DOWN = "thumbs-down";
    public static final String ACTION_SKIP = "skip";

    private static final String TAG = "AudioSource";

    public String id;
    public String source;
    public String streamBaseUrl;
    public AudioMetadata audioMetadata;
    public boolean useForNotification;
    public boolean isBackgroundMusic;
    public boolean loopAudio = false;

    public String onPlaybackStatusChangeCallbackId;
    public String onReadyCallbackId;
    public String onEndCallbackId;

    private AudioPlayerPlugin pluginOwner;
    // Set by MediaSessionCallback after the source is registered with the
    // session (SET_AUDIO_SOURCES for the notification source, CREATE_PLAYER
    // for non-notification sources). Null until then; nothing reads it
    // before SET_AUDIO_SOURCES has run.
    private AudioPlayerService service;

    private Player player;
    private PlayerEventListener playerEventListener;

    private boolean isPlaying = false;
    private boolean isStopped = true;

    public AudioSource(
        AudioPlayerPlugin pluginOwner,
        String id,
        String source,
        String streamBaseUrl,
        AudioMetadata audioMetadata,
        boolean useForNotification,
        boolean isBackgroundMusic,
        boolean loopAudio
    ) {
        this.pluginOwner = pluginOwner;
        this.id = id;
        this.source = source;
        this.streamBaseUrl = streamBaseUrl;
        this.audioMetadata = audioMetadata;
        this.useForNotification = useForNotification;
        this.isBackgroundMusic = isBackgroundMusic;
        this.loopAudio = loopAudio;

        this.audioMetadata.setPluginOwner(pluginOwner).setUpdateCallBack(this::onMetadataUpdated);
    }

    public void initialize(Context context) {
        if (useForNotification || player != null) {
            return;
        }

        setIsStopped();

        player = new ExoPlayer.Builder(context).setWakeMode(C.WAKE_MODE_NETWORK).build();
        setPlayerAttributes();

        player.prepare();
    }

    public void setPlayerAttributes() {
        player.setAudioAttributes(
            new AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(
                    useForNotification ? C.AUDIO_CONTENT_TYPE_SPEECH : C.AUDIO_CONTENT_TYPE_MUSIC
                )
                .build(),
            useForNotification
        );

        player.setMediaItem(buildMediaItem());
        player.setRepeatMode(loopAudio ? ExoPlayer.REPEAT_MODE_ONE : ExoPlayer.REPEAT_MODE_OFF);
        player.setPlayWhenReady(false);
        player.addListener(new PlayerEventListener(pluginOwner, this));
    }

    public void changeAudioSource(String newSource) {
        source = newSource;

        Player player = getPlayer();

        player.setMediaItem(buildMediaItem());
        player.setPlayWhenReady(false);
        player.prepare();
    }

    public float getDuration() {
        long duration = getPlayer().getDuration();

        if (duration == C.TIME_UNSET) {
            return -1;
        }

        return duration / 1000.0f;
    }

    public float getCurrentTime() {
        return getPlayer().getCurrentPosition() / 1000.0f;
    }

    public void play() {
        setIsPlaying();

        Player player = getPlayer();

        if (player.getPlaybackState() == Player.STATE_IDLE) {
            // MediaController.getCurrentMediaItem() can return null after a
            // prior stop(); re-seat the item so the metadata poller's
            // replaceMediaItem() has a target.
            player.setMediaItem(buildMediaItem());
            player.prepare();
        }

        player.play();

        if (useForNotification) {
            audioMetadata.startUpdater();
        }
    }

    public void pause() {
        setIsPaused();
        getPlayer().pause();
        audioMetadata.stopUpdater();
    }

    public void seek(long timeInSeconds) {
        getPlayer().seekTo(timeInSeconds * 1000);
    }

    public void stop() {
        Log.i(TAG, "stop() entered, isPlaying=" + isPlaying);
        setIsStopped();

        // player.stop() (vs pause+seekToDefault) puts the player into IDLE
        // and releases the network connection, so the next play() forces a
        // fresh prepare()/connect — required for live streams where any
        // buffered audio is stale and where the server-side registry needs
        // to clear so the polling endpoint returns channel metadata.
        Player player = getPlayer();
        player.stop();
        audioMetadata.stopUpdater();
    }

    public void setVolume(float volume) {
        getPlayer().setVolume(volume);
    }

    public void setRate(float rate) {
        getPlayer().setPlaybackSpeed(rate);
    }

    public void setOnReady(String callbackId) {
        onReadyCallbackId = callbackId;
    }

    public void setOnEnd(String callbackId) {
        onEndCallbackId = callbackId;
    }

    public void setOnPlaybackStatusChange(String callbackId) {
        onPlaybackStatusChangeCallbackId = callbackId;
    }

    public boolean isPlaying() {
        if (getPlayer() == null) {
            return false;
        }

        return isPlaying;
    }

    public boolean isPaused() {
        return !isPlaying && !isStopped;
    }

    public boolean isStopped() {
        return isStopped;
    }

    public void setIsPlaying() {
        this.isStopped = false;
        this.isPlaying = true;
    }

    public void setIsPaused() {
        this.isStopped = false;
        this.isPlaying = false;
    }

    public void setIsStopped() {
        this.isStopped = true;
        this.isPlaying = false;
    }

    public Player getPlayer() {
        return player;
    }

    public void setPlayer(Player player) {
        this.player = player;
    }

    public void releasePlayer() {
        if (player != null) {
            player.release();
            player = null;
            playerEventListener = null;
        }
    }

    public void setEventListener(PlayerEventListener listener) {
        playerEventListener = listener;
    }

    public PlayerEventListener getEventListener() {
        return playerEventListener;
    }

    public boolean isInitialized() {
        return getPlayer() != null;
    }

    public AudioPlayerService getService() {
        return service;
    }

    public void setService(AudioPlayerService service) {
        this.service = service;
    }

    public MediaItem buildMediaItem() {
        return new MediaItem.Builder().setMediaMetadata(getMediaMetadata()).setUri(source).build();
    }

    public void destroy() {
        audioMetadata.stopUpdater();

        if (!useForNotification) {
            releasePlayer();
        }
    }

    // performAction POSTs the listener's button press to soundz-good. The
    // request runs on the plugin's executor, off the Media3 main thread.
    // On a successful skip — or downvote of a may-skip track — the player
    // flushes its buffered audio and re-prepares so the listener hears the
    // new playlist position immediately, matching the in-app pause/play
    // dance in Player.vue.
    public void performAction(String action) {
        if (streamBaseUrl == null || streamBaseUrl.isEmpty()) {
            Log.w(TAG, "performAction: no streamBaseUrl, dropping " + action);
            return;
        }
        String trackId = audioMetadata.trackId;
        if (trackId == null || trackId.isEmpty()) {
            Log.w(TAG, "performAction: no current trackId, dropping " + action);
            return;
        }

        boolean flushAfter = ACTION_SKIP.equals(action) ||
            (ACTION_THUMBS_DOWN.equals(action) && audioMetadata.maySkip);

        pluginOwner.executorService.submit(() -> {
            String suffix;
            String body;
            switch (action) {
                case ACTION_SKIP:
                    suffix = "/skip/" + trackId;
                    body = null;
                    break;
                case ACTION_THUMBS_UP:
                    suffix = "/vote/" + trackId;
                    body = new JSObject().put("value", "up").toString();
                    break;
                case ACTION_THUMBS_DOWN:
                    suffix = "/vote/" + trackId;
                    body = new JSObject().put("value", "down").toString();
                    break;
                default:
                    Log.w(TAG, "performAction: unknown action " + action);
                    return;
            }

            HttpURLConnection conn = null;
            try {
                URL url = new URL(streamBaseUrl + suffix);
                conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setDoOutput(body != null);
                if (body != null) {
                    conn.setRequestProperty("Content-Type", "application/json");
                    try (OutputStreamWriter w = new OutputStreamWriter(conn.getOutputStream(), StandardCharsets.UTF_8)) {
                        w.write(body);
                    }
                }
                int status = conn.getResponseCode();
                if (status < 200 || status >= 300) {
                    Log.w(TAG, "performAction: " + action + " -> HTTP " + status);
                    return;
                }
                // Re-check on the main thread before flushing: if the user
                // paused while the HTTP request was in flight, flushAndReplay
                // would force playback to resume against their intent. The
                // vote/skip itself is already recorded server-side; the next
                // user-initiated play() will pick up the new playlist
                // position fresh anyway since pause releases the stream.
                if (flushAfter) {
                    new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                        if (isPlaying) {
                            flushAndReplay();
                        }
                    });
                }
            } catch (Exception ex) {
                Log.e(TAG, "performAction: " + action + " failed", ex);
            } finally {
                if (conn != null) {
                    conn.disconnect();
                }
            }
        });
    }

    // flushAndReplay drops any buffered audio and reconnects to /stream so
    // the listener hears the new playlist position right after a skip or
    // downvote-with-may_skip. The MediaItem is reseated explicitly: stop()
    // alone does not clear the player's loaded MediaItem, and prepare() on
    // the same instance can resume from already-fetched state instead of
    // opening a fresh DataSource, leaving the listener on the just-skipped
    // track. The in-app pause/play path reseats via AudioSource.play()'s
    // STATE_IDLE branch — that branch isn't reliable here because the
    // MediaController's state lags the underlying ExoPlayer when stop()
    // and play() run on the same main-thread tick, so we reseat
    // unconditionally.
    //
    // Known: AudioMetadata.stopUpdater schedules a 1s delayed final poll
    // before play()'s startUpdater fires its first request. The delayed
    // poll mutates fields concurrently with the new poller, leaving a
    // brief window of stale "between tracks" metadata on the lockscreen
    // right after a flush. Acceptable because the next regular poll
    // overwrites within ~10s; a real fix would cancel the delayed poll
    // when the updater restarts.
    private void flushAndReplay() {
        Player player = getPlayer();
        if (player == null) {
            return;
        }
        player.stop();
        player.setMediaItem(buildMediaItem());
        player.prepare();
        player.play();
    }

    private void onMetadataUpdated() {
        Player player = getPlayer();
        if (player == null) {
            Log.i(TAG, "onMetadataUpdated called, player null=true");
            return;
        }

        MediaItem currentMediaItem = player.getCurrentMediaItem();
        Log.i(
            TAG,
            "onMetadataUpdated called, currentMediaItem null=" +
            (currentMediaItem == null) +
            ", title=" +
            audioMetadata.title
        );
        if (currentMediaItem == null) {
            // Happens during quick channel switches: the player exists but
            // setMediaItem hasn't run yet (or the queue was cleared). The new
            // metadata is already stored on audioMetadata and will flow through
            // getMediaMetadata() when buildMediaItem() is next called.
            return;
        }

        MediaItem newMediaItem = currentMediaItem
            .buildUpon()
            .setMediaMetadata(getMediaMetadata())
            .build();

        player.replaceMediaItem(0, newMediaItem);

        if (useForNotification && service != null) {
            service.setCustomActionEnabled(ACTION_SKIP, isPlaying && audioMetadata.maySkip);
        }
    }

    public JSObject toCurrentTrackEvent() {
        JSObject track = new JSObject();
        track.put("id", audioMetadata.trackId);
        track.put("artist", audioMetadata.artist);
        track.put("title", audioMetadata.title);
        track.put("album", audioMetadata.album);
        track.put("image_url", audioMetadata.imageUrl);
        track.put("may_skip", audioMetadata.maySkip);
        track.put("is_ad", audioMetadata.isAd);
        track.put("target_url", audioMetadata.targetUrl);

        JSObject result = new JSObject();
        result.put("channel_id", audioMetadata.channelId);
        result.put("track", track);
        return result;
    }

    private MediaMetadata getMediaMetadata() {
        MediaMetadata.Builder builder = new MediaMetadata.Builder()
            .setArtist(audioMetadata.artist == null ? "" : audioMetadata.artist)
            .setTitle(audioMetadata.title == null ? "" : audioMetadata.title)
            .setAlbumTitle(audioMetadata.album == null ? "" : audioMetadata.album);

        if (useForNotification && audioMetadata.imageUrl != null && !audioMetadata.imageUrl.isEmpty()) {
            try {
                if (audioMetadata.imageUrl.startsWith("http")) {
                    builder.setArtworkUri(Uri.parse(audioMetadata.imageUrl));
                } else {
                    int bufferLength = 4 * 0x400;
                    byte[] buffer = new byte[bufferLength];
                    int readLength;
                    ByteArrayOutputStream outputStream = new ByteArrayOutputStream();

                    InputStream inputStream = pluginOwner
                        .getContext()
                        .getAssets()
                        .open("public/" + audioMetadata.imageUrl);

                    while ((readLength = inputStream.read(buffer, 0, bufferLength)) != -1) {
                        outputStream.write(buffer, 0, readLength);
                    }

                    inputStream.close();

                    builder.maybeSetArtworkData(
                        outputStream.toByteArray(),
                        MediaMetadata.PICTURE_TYPE_OTHER
                    );
                }
            } catch (Exception ex) {
                Log.w(TAG, "Could not load the artwork source.", ex);
            }
        }

        return builder.build();
    }
}
