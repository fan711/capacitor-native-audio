package us.mediagrid.capacitorjs.plugins.nativeaudio;

import static androidx.media3.common.Player.*;

import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;

public class PlayerEventListener implements Listener {

    private static final String TAG = "PlayerEventListener";

    private AudioPlayerPlugin plugin;
    private AudioSource audioSource;

    public PlayerEventListener(AudioPlayerPlugin plugin, AudioSource audioSource) {
        this.plugin = plugin;
        this.audioSource = audioSource;
        this.audioSource.setEventListener(this);
    }

    @Override
    public void onIsPlayingChanged(boolean isPlaying) {
        if (!audioSource.isInitialized()) {
            makeCall(
                audioSource.onPlaybackStatusChangeCallbackId,
                new JSObject().put("status", "stopped")
            );
            return;
        }

        // Drive the metadata poller off the player's true state so the
        // native notification/lockscreen pause (ForwardingPlayer.pause() ->
        // stop()) takes the same path as the in-app stop: polling stops and
        // the delayed one-shot resync fires. Reading audioSource.isPlaying()
        // here would miss the native path, which never updates that field.
        String status;
        if (isPlaying) {
            audioSource.setIsPlaying();
            audioSource.audioMetadata.startUpdater();
            status = "playing";
        } else {
            int state = audioSource.getPlayer().getPlaybackState();
            if (state == STATE_READY && !audioSource.getPlayer().getPlayWhenReady()) {
                audioSource.setIsPaused();
                status = "paused";
            } else {
                audioSource.setIsStopped();
                status = "stopped";
            }
            audioSource.audioMetadata.stopUpdater();
        }

        if (audioSource.useForNotification) {
            AudioPlayerService service = audioSource.getService();
            if (service != null) {
                service.setCustomActionEnabled(AudioSource.ACTION_THUMBS_UP, isPlaying);
                service.setCustomActionEnabled(AudioSource.ACTION_THUMBS_DOWN, isPlaying);
                service.setCustomActionEnabled(AudioSource.ACTION_SKIP, isPlaying && audioSource.audioMetadata.maySkip);
            }
        }

        makeCall(
            audioSource.onPlaybackStatusChangeCallbackId,
            new JSObject().put("status", status)
        );
    }

    @Override
    public void onPlaybackStateChanged(@State int playbackState) {
        if (playbackState == STATE_READY) {
            makeCall(audioSource.onReadyCallbackId);
        }

        if (playbackState == STATE_ENDED) {
            audioSource.getPlayer().stop();
            audioSource.getPlayer().seekToDefaultPosition();
            audioSource.setIsStopped();
            audioSource.audioMetadata.stopUpdater();

            makeCall(audioSource.onEndCallbackId);
        }
    }

    private void makeCall(String callbackId) {
        makeCall(callbackId, new JSObject());
    }

    private void makeCall(String callbackId, JSObject data) {
        if (callbackId == null) {
            return;
        }

        PluginCall call = plugin.getBridge().getSavedCall(callbackId);

        if (call == null) {
            return;
        }

        if (data.length() == 0) {
            call.resolve();
        } else {
            call.resolve(data);
        }
    }
}
