package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.app.PendingIntent;
import android.content.Intent;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.ForwardingPlayer;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.CommandButton;
import androidx.media3.session.MediaSession;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.MediaSessionService;
import com.google.common.collect.ImmutableList;

public class AudioPlayerService extends MediaSessionService {

    private static final String TAG = "AudioPlayerService";
    public static final String PLAYBACK_CHANNEL_ID = "playback_channel";
    private MediaSession mediaSession = null;

    // The three listener-action buttons surfaced on the notification /
    // lockscreen. Order mirrors Player.vue's button row: thumbs-up,
    // thumbs-down, skip. The buttons live for the lifetime of the service;
    // setCustomActionEnabled rebuilds individual buttons in place to flip
    // their enabled flag (CommandButton is immutable).
    private CommandButton thumbsUpButton;
    private CommandButton thumbsDownButton;
    private CommandButton skipButton;

    @OptIn(markerClass = UnstableApi.class)
    @Override
    public void onCreate() {
        Log.i(TAG, "Service being created");
        super.onCreate();

        String packageName = getApplicationContext().getPackageName();
        Intent sessionActivityIntent = getPackageManager().getLaunchIntentForPackage(packageName);

        PendingIntent sessionActivityPendingIntent = PendingIntent.getActivity(
            this,
            0,
            sessionActivityIntent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );

        ExoPlayer exoPlayer = new ExoPlayer.Builder(this)
            .setAudioAttributes(
                new AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
                    .build(),
                true
            )
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build();
        exoPlayer.setPlayWhenReady(false);

        // Every pause routed through this player — whether from the in-app
        // button or the native notification/lockscreen controls — becomes a
        // full stop() so the live-stream network connection is released.
        // The paired play() override re-prepares from IDLE so the next play
        // fetches the current broadcast moment rather than resuming stale
        // buffered audio. The MediaSession stays alive, so the notification
        // remains visible across the stop/play cycle.
        //
        // The seek-to-prev/next commands are stripped from the advertised
        // command set: ExoPlayer briefly reports SEEK_TO_PREVIOUS as
        // available during the stop -> setMediaItem -> prepare transition
        // that flushAndReplay() drives, which makes the framework flash a
        // "previous track" affordance into the lockscreen for the duration
        // of a skip. There is nothing previous to seek to on a live stream
        // with a single MediaItem, so masking the commands at the player
        // suppresses the flash everywhere (notification, Auto, Wear) at
        // once.
        Player sessionPlayer = new ForwardingPlayer(exoPlayer) {
            @Override
            public void pause() {
                stop();
            }

            @Override
            public void play() {
                if (getPlaybackState() == Player.STATE_IDLE) {
                    prepare();
                }
                super.play();
            }

            @Override
            public Player.Commands getAvailableCommands() {
                return super.getAvailableCommands().buildUpon()
                    .removeAll(
                        Player.COMMAND_SEEK_TO_PREVIOUS,
                        Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                        Player.COMMAND_SEEK_TO_NEXT,
                        Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM
                    )
                    .build();
            }

            @Override
            public boolean isCommandAvailable(int command) {
                if (command == Player.COMMAND_SEEK_TO_PREVIOUS
                    || command == Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM
                    || command == Player.COMMAND_SEEK_TO_NEXT
                    || command == Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM) {
                    return false;
                }
                return super.isCommandAvailable(command);
            }
        };

        thumbsUpButton = buildCommandButton(
            MediaSessionCallback.CUSTOM_THUMBS_UP,
            R.drawable.ic_action_thumb_up,
            "Thumbs up",
            true
        );
        thumbsDownButton = buildCommandButton(
            MediaSessionCallback.CUSTOM_THUMBS_DOWN,
            R.drawable.ic_action_thumb_down,
            "Thumbs down",
            true
        );
        skipButton = buildCommandButton(
            MediaSessionCallback.CUSTOM_SKIP,
            R.drawable.ic_action_skip_next,
            "Skip",
            true
        );
        // Without explicit slot hints Media3 defaults the first custom
        // button to SLOT_BACK (left of play/pause). Pin all three to
        // forward slots so the row reads play/pause | thumbs-up |
        // thumbs-down | skip from the play button outward.

        mediaSession = new MediaSession.Builder(this, sessionPlayer)
            .setCallback(new MediaSessionCallback(this))
            .setSessionActivity(sessionActivityPendingIntent)
            .setCustomLayout(getCustomLayout())
            .build();

        setMediaNotificationProvider(new SoundzNotificationProvider(this));
        // Note: the small status-bar icon is overridden by providing a
        // drawable named `media3_notification_small_icon` in the plugin's
        // res/drawable, which the Media3 default provider picks up.
    }

    @OptIn(markerClass = UnstableApi.class)
    private CommandButton buildCommandButton(String sessionCommand, int iconRes, String displayName, boolean enabled) {
        // All three listener-action buttons request the same slot list so
        // none of them lands in SLOT_BACK (left of play/pause). The order
        // they appear in setCustomLayout determines which one wins
        // SLOT_FORWARD_SECONDARY; the rest spill into SLOT_OVERFLOW (the
        // ⋮ menu).
        int[] slots = new int[] { CommandButton.SLOT_FORWARD_SECONDARY, CommandButton.SLOT_OVERFLOW };
        return new CommandButton.Builder()
            .setSessionCommand(new SessionCommand(sessionCommand, new Bundle()))
            .setIconResId(iconRes)
            .setDisplayName(displayName)
            .setSlots(slots)
            .setEnabled(enabled)
            .build();
    }

    @OptIn(markerClass = UnstableApi.class)
    public ImmutableList<CommandButton> getCustomLayout() {
        return ImmutableList.of(thumbsUpButton, thumbsDownButton, skipButton);
    }

    // setCustomActionEnabled flips the enabled flag for one of the three
    // listener-action buttons and pushes the rebuilt layout to all
    // controllers. CommandButton is immutable so we reconstruct the affected
    // button in place.
    @OptIn(markerClass = UnstableApi.class)
    public void setCustomActionEnabled(String action, boolean enabled) {
        switch (action) {
            case AudioSource.ACTION_THUMBS_UP:
                if (thumbsUpButton.isEnabled == enabled) return;
                thumbsUpButton = buildCommandButton(
                    MediaSessionCallback.CUSTOM_THUMBS_UP, R.drawable.ic_action_thumb_up, "Thumbs up", enabled);
                break;
            case AudioSource.ACTION_THUMBS_DOWN:
                if (thumbsDownButton.isEnabled == enabled) return;
                thumbsDownButton = buildCommandButton(
                    MediaSessionCallback.CUSTOM_THUMBS_DOWN, R.drawable.ic_action_thumb_down, "Thumbs down", enabled);
                break;
            case AudioSource.ACTION_SKIP:
                if (skipButton.isEnabled == enabled) return;
                skipButton = buildCommandButton(
                    MediaSessionCallback.CUSTOM_SKIP, R.drawable.ic_action_skip_next, "Skip", enabled);
                break;
            default:
                return;
        }
        if (mediaSession != null) {
            mediaSession.setCustomLayout(getCustomLayout());
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "Service starting");

        return super.onStartCommand(intent, flags, startId);
    }

    @Override
    public MediaSession onGetSession(MediaSession.ControllerInfo controllerInfo) {
        return mediaSession;
    }

    @Override
    public void onTaskRemoved(@Nullable Intent rootIntent) {
        Log.i(TAG, "Task removed");

        AudioSources audioSources = getAudioSourcesFromMediaSession();

        if (audioSources != null) {
            Log.i(TAG, "Destroying all non-notification audio sources");
            audioSources.destroyAllNonNotificationSources();
        }

        Player player = mediaSession.getPlayer();

        // Make sure the service is not in foreground
        if (player.getPlayWhenReady()) {
            player.pause();
        }

        stopSelf();
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "Service being destroyed");

        AudioSources audioSources = getAudioSourcesFromMediaSession();

        if (audioSources != null) {
            Log.i(TAG, "Destroying all non-notification audio sources");
            audioSources.destroyAllNonNotificationSources();
        }

        mediaSession.getPlayer().release();
        mediaSession.release();
        mediaSession = null;

        super.onDestroy();
    }

    public AudioSource getNotificationAudioSource() {
        AudioSources sources = getAudioSourcesFromMediaSession();
        if (sources == null) return null;
        return sources.forNotification();
    }

    @OptIn(markerClass = UnstableApi.class)
    private AudioSources getAudioSourcesFromMediaSession() {
        IBinder sourcesBinder = mediaSession.getSessionExtras().getBinder("audioSources");

        if (sourcesBinder != null) {
            return (AudioSources) sourcesBinder;
        }

        return null;
    }
}
