package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.os.Bundle;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.session.MediaSession;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.SessionCommands;
import androidx.media3.session.SessionResult;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;

public class MediaSessionCallback implements MediaSession.Callback {

    public static final String SET_AUDIO_SOURCES = "SetAudioSources";
    public static final String CREATE_PLAYER = "CreatePlayer";
    public static final String CUSTOM_THUMBS_UP = "CustomThumbsUp";
    public static final String CUSTOM_THUMBS_DOWN = "CustomThumbsDown";
    public static final String CUSTOM_SKIP = "CustomSkip";

    private AudioPlayerService audioService;

    public MediaSessionCallback(AudioPlayerService audioService) {
        this.audioService = audioService;
    }

    @OptIn(markerClass = UnstableApi.class)
    @Override
    public MediaSession.ConnectionResult onConnect(
        MediaSession session,
        MediaSession.ControllerInfo controller
    ) {
        SessionCommands sessionCommands =
            MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                .add(new SessionCommand(SET_AUDIO_SOURCES, new Bundle()))
                .add(new SessionCommand(CREATE_PLAYER, new Bundle()))
                .add(new SessionCommand(CUSTOM_THUMBS_UP, new Bundle()))
                .add(new SessionCommand(CUSTOM_THUMBS_DOWN, new Bundle()))
                .add(new SessionCommand(CUSTOM_SKIP, new Bundle()))
                .build();

        return new MediaSession.ConnectionResult.AcceptedResultBuilder(session)
            .setAvailableSessionCommands(sessionCommands)
            .setCustomLayout(audioService.getCustomLayout())
            .build();
    }

    @Override
    public ListenableFuture<SessionResult> onCustomCommand(
        MediaSession session,
        MediaSession.ControllerInfo controller,
        SessionCommand customCommand,
        Bundle args
    ) {
        String action = customCommand.customAction;

        if (action.equals(SET_AUDIO_SOURCES)) {
            Bundle audioSouresBundle = new Bundle();
            AudioSources audioSources = (AudioSources) customCommand.customExtras.getBinder("audioSources");
            audioSouresBundle.putBinder("audioSources", audioSources);

            session.setSessionExtras(audioSouresBundle);

            // Inject the service back-reference into every registered source
            // so AudioSource and PlayerEventListener can flip OS button enable
            // state without going through a static singleton.
            AudioSource notif = audioSources.forNotification();
            if (notif != null) {
                notif.setService(audioService);
            }
        } else if (action.equals(CREATE_PLAYER)) {
            AudioSource source = (AudioSource) customCommand.customExtras.getBinder("audioSource");
            source.setService(audioService);
            source.initialize(audioService);
        } else if (isListenerActionCommand(action)) {
            AudioSource notificationSource = audioService.getNotificationAudioSource();
            if (notificationSource != null) {
                notificationSource.performAction(commandToAction(action));
            }
        }

        return Futures.immediateFuture(new SessionResult(SessionResult.RESULT_SUCCESS));
    }

    private static boolean isListenerActionCommand(String action) {
        return action.equals(CUSTOM_THUMBS_UP) ||
            action.equals(CUSTOM_THUMBS_DOWN) ||
            action.equals(CUSTOM_SKIP);
    }

    private static String commandToAction(String command) {
        switch (command) {
            case CUSTOM_THUMBS_UP: return AudioSource.ACTION_THUMBS_UP;
            case CUSTOM_THUMBS_DOWN: return AudioSource.ACTION_THUMBS_DOWN;
            case CUSTOM_SKIP: return AudioSource.ACTION_SKIP;
            default: return "";
        }
    }
}
