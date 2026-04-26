package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.content.Context;
import androidx.annotation.OptIn;
import androidx.core.app.NotificationCompat;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.session.CommandButton;
import androidx.media3.session.DefaultMediaNotificationProvider;
import androidx.media3.session.MediaNotification;
import androidx.media3.session.MediaSession;
import com.google.common.collect.ImmutableList;

// SoundzNotificationProvider forces button order in the lockscreen /
// notification by overriding addNotificationActions. Media3's
// CommandButton.setSlots is only a hint — the default provider's compact
// view doesn't reliably honor SLOT_FORWARD_SECONDARY for custom buttons,
// and the framework's auto-balancing puts items on whichever side of
// play/pause has fewer buttons.
//
// Other media apps surface a back button + progress + forward button
// around play/pause; we have no transport-style back button, so the
// framework distributes our three custom buttons asymmetrically. The
// pragmatic compromise: explicitly anchor skip on the LEFT (it reads
// like a "next/forward" but in the absence of a back button, putting it
// alone on one side keeps the two thumbs together on the other), and
// the two thumbs together on the RIGHT.
@OptIn(markerClass = UnstableApi.class)
public class SoundzNotificationProvider extends DefaultMediaNotificationProvider {

    public SoundzNotificationProvider(Context context) {
        super(context);
    }

    @Override
    protected int[] addNotificationActions(
        MediaSession mediaSession,
        ImmutableList<CommandButton> mediaButtons,
        NotificationCompat.Builder builder,
        MediaNotification.ActionFactory actionFactory
    ) {
        CommandButton thumbsUp = null;
        CommandButton thumbsDown = null;
        CommandButton skip = null;
        ImmutableList.Builder<CommandButton> rest = ImmutableList.builder();

        for (CommandButton button : mediaButtons) {
            String action = button.sessionCommand != null ? button.sessionCommand.customAction : "";
            if (MediaSessionCallback.CUSTOM_THUMBS_UP.equals(action)) {
                thumbsUp = button;
            } else if (MediaSessionCallback.CUSTOM_THUMBS_DOWN.equals(action)) {
                thumbsDown = button;
            } else if (MediaSessionCallback.CUSTOM_SKIP.equals(action)) {
                skip = button;
            } else {
                rest.add(button);
            }
        }

        // The framework auto-balances the layout around play/pause: with
        // no transport-style back button, our customs split with one on
        // the left and the rest on the right. Putting thumbs-up first
        // sends it to the left of play/pause, and the (semantically
        // similar) thumbs-down + skip pair stays together on the right.
        ImmutableList.Builder<CommandButton> ordered = ImmutableList.builder();
        if (thumbsUp != null) ordered.add(thumbsUp);
        ordered.addAll(rest.build());
        if (thumbsDown != null) ordered.add(thumbsDown);
        if (skip != null) ordered.add(skip);

        return super.addNotificationActions(mediaSession, ordered.build(), builder, actionFactory);
    }
}
