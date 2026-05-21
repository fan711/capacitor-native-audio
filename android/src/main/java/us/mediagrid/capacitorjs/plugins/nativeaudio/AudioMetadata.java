package us.mediagrid.capacitorjs.plugins.nativeaudio;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.plugin.util.HttpRequestHandler;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

// AudioMetadata fetches a 2-minute lookahead of upcoming track changes from
// soundz-good's /metadata-upcoming endpoint every 60 s, holds the items in
// a local queue, and applies each to the OS MediaSession at its own from_us
// via a self-rearming apply Handler. AudioSource and AudioPlayerService still
// read the current track via the same field surface (artist, title, trackId,
// …) — those fields are written by the apply timer whenever a new group
// becomes current.
//
// Queue is dropped on stop/play/skip (the old timeline is stale); the next
// refresh repopulates it. Apply-timer fires also drop entries whose to_us
// is in the past, so the queue stays small.
public class AudioMetadata {

    private static final String TAG = "AudioMetadata";

    // Silent shade-only ad-indicator notification. Gated on `is_ad` AND a
    // non-empty `target_url`: the backend now populates target_url for any
    // track with a click destination (ads and songs alike), so is_ad is what
    // distinguishes "show the ad shade" from a song's in-app click-through.
    private static final String AD_CHANNEL_ID = "now_playing_passive";
    private static final int AD_NOTIFICATION_ID = 9912;

    private static final int REFRESH_INTERVAL_MS = 60 * 1000;

    public String channelId = "";
    public String trackId = "";
    public String artist = "";
    public String title = "";
    public String album = "";
    // Default to the bundled favicon as the lockscreen artwork until the
    // first /metadata-upcoming poll lands a real image_url.
    public String imageUrl = "favicon.png";
    public boolean maySkip = true;
    public boolean isAd = false;
    public String targetUrl = "";

    public String updateUrl;

    private final List<UpcomingMetadataItem> queue = new ArrayList<>();

    private Handler refreshHandler = null;
    private Runnable refreshRunner = null;
    private Handler applyHandler = null;
    private Runnable applyRunner = null;
    private Runnable updateCallback = null;

    private AudioPlayerPlugin pluginOwner;

    private boolean pollerActive = false;
    private String previousNotifiedTrackId = "";

    AudioMetadata(String updateUrl) {
        this.updateUrl = updateUrl;
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
        if (!hasUpdateUrl() || refreshHandler != null) {
            return;
        }

        pollerActive = true;
        refreshHandler = new Handler(Looper.getMainLooper());
        applyHandler = new Handler(Looper.getMainLooper());
        refreshRunner = new Runnable() {
            @Override
            public void run() {
                makeUpdateRequest(() -> {
                    if (refreshHandler != null) {
                        refreshHandler.postDelayed(this, REFRESH_INTERVAL_MS);
                    }
                });
            }
        };

        // 1s delay lets the stream warm up server-side (the forwarder's
        // first items reach Redis) before the first poll, so the lockscreen
        // picks up real metadata on the very first request.
        refreshHandler.postDelayed(refreshRunner, 1000);
    }

    public void stopUpdater() {
        if (refreshHandler == null) {
            return;
        }

        pollerActive = false;
        clearTrackNotification();
        refreshHandler.removeCallbacks(refreshRunner);
        refreshHandler = null;
        refreshRunner = null;
        if (applyHandler != null && applyRunner != null) {
            applyHandler.removeCallbacks(applyRunner);
        }
        applyHandler = null;
        applyRunner = null;

        // Drop the queue: the next session's timeline is unrelated.
        synchronized (queue) {
            queue.clear();
        }

        // One delayed final poll so the OS audio controls catch up to the
        // server's post-disconnect state (e.g. soundz-good returning channel
        // metadata after the stream connection closes and Deregister fires).
        if (hasUpdateUrl()) {
            new Handler(Looper.getMainLooper()).postDelayed(
                () -> makeUpdateRequest(null),
                1000
            );
        }
    }

    public boolean hasUpdateUrl() {
        return updateUrl != null && !updateUrl.isEmpty();
    }

    // Force a one-shot refresh — same semantics as before, used by the
    // foreground-resume path on the JS side.
    public void updateMetadataByUrl(Runnable requeueCallback) {
        makeUpdateRequest(requeueCallback);
    }

    private void makeUpdateRequest(Runnable requeueCallback) {
        if (pluginOwner.executorService.isShutdown()) {
            return;
        }

        pluginOwner.executorService.submit(() -> {
            Log.i(TAG, "poll firing for URL=" + updateUrl);
            try {
                fetchAndApplyWindow();
            } catch (Exception ex) {
                Log.e(TAG, "There was an error running the metadata update", ex);
            } finally {
                // Always requeue — a single failed poll (e.g. 404 during
                // stream startup race) must not kill the poller permanently.
                if (requeueCallback != null) {
                    requeueCallback.run();
                }
            }
        });
    }

    private void fetchAndApplyWindow() {
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
                return;
            }

            JSObject json = new JSObject(
                HttpRequestHandler.readStreamAsString(urlConnection.getInputStream())
            );

            String newChannelId = stringOrEmpty(json.getString("channel_id"));
            List<UpcomingMetadataItem> newQueue = new ArrayList<>();
            JSONArray items = json.optJSONArray("items");
            if (items != null) {
                for (int i = 0; i < items.length(); i++) {
                    JSONObject obj = items.optJSONObject(i);
                    if (obj == null) continue;
                    newQueue.add(UpcomingMetadataItem.fromJson(obj));
                }
            }
            Collections.sort(newQueue, (a, b) -> Long.compare(a.fromUs, b.fromUs));

            synchronized (queue) {
                queue.clear();
                queue.addAll(newQueue);
            }
            channelId = newChannelId;

            // Apply the now-active entry immediately (the refresh landed
            // mid-group; the previous queue's current item may have
            // differed) and arm the apply timer for the next transition.
            new Handler(Looper.getMainLooper()).post(() -> {
                fireMetadataUpdated();
                scheduleNextApply();
            });
        } catch (Exception ex) {
            Log.e(TAG, "An error occurred trying to get updated metadata", ex);
        } finally {
            if (urlConnection != null) {
                urlConnection.disconnect();
            }
        }
    }

    // scheduleNextApply prunes outdated entries and arms a one-shot post
    // for the next item whose from_us is in the future. The post handler
    // fires fireMetadataUpdated() and re-arms — so there's only ever one
    // pending applyHandler callback.
    private void scheduleNextApply() {
        if (applyHandler == null) return;
        if (applyRunner != null) {
            applyHandler.removeCallbacks(applyRunner);
            applyRunner = null;
        }

        long nowUs = nowUs();
        UpcomingMetadataItem next;
        synchronized (queue) {
            Iterator<UpcomingMetadataItem> it = queue.iterator();
            while (it.hasNext()) {
                if (it.next().toUs < nowUs) {
                    it.remove();
                }
            }
            next = null;
            for (UpcomingMetadataItem item : queue) {
                if (item.fromUs > nowUs) {
                    next = item;
                    break;
                }
            }
        }
        if (next == null) return;

        long delayMs = Math.max(0, (next.fromUs - nowUs) / 1000);
        applyRunner = () -> {
            fireMetadataUpdated();
            scheduleNextApply();
        };
        applyHandler.postDelayed(applyRunner, delayMs);
    }

    private void fireMetadataUpdated() {
        applyCurrentItem();
        syncTrackNotification();
        if (updateCallback != null) {
            updateCallback.run();
        }
    }

    // applyCurrentItem copies the queue entry covering "now" into the public
    // fields AudioSource / AudioPlayerService read. When no entry covers now,
    // leave the last-applied values in place — the lockscreen continues
    // showing the previous track until the next refresh closes the gap.
    private void applyCurrentItem() {
        long nowUs = nowUs();
        UpcomingMetadataItem current = null;
        synchronized (queue) {
            for (UpcomingMetadataItem item : queue) {
                if (item.fromUs <= nowUs && nowUs <= item.toUs) {
                    current = item;
                    break;
                }
            }
        }
        if (current == null) {
            return;
        }
        trackId = current.id;
        artist = current.artist;
        title = current.title;
        album = current.album;
        imageUrl = current.imageUrl;
        maySkip = current.maySkip;
        isAd = current.isAd;
        targetUrl = current.targetUrl;
    }

    private static long nowUs() {
        return System.currentTimeMillis() * 1000L;
    }

    private static String stringOrEmpty(String s) {
        return s == null ? "" : s;
    }

    private Context notificationContext() {
        if (pluginOwner == null) return null;
        Context ctx = pluginOwner.getContext();
        return ctx == null ? null : ctx.getApplicationContext();
    }

    private void ensureNotificationChannel(Context ctx, NotificationManager nm) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        if (nm.getNotificationChannel(AD_CHANNEL_ID) != null) return;
        NotificationChannel channel = new NotificationChannel(
            AD_CHANNEL_ID,
            "Now playing",
            NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Quietly indicates the currently playing track. Silent, no banner.");
        channel.setSound(null, null);
        channel.enableVibration(false);
        nm.createNotificationChannel(channel);
    }

    private void syncTrackNotification() {
        if (!pollerActive) return;

        Context ctx = notificationContext();
        if (ctx == null) return;
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        // Gate is is_ad AND a click destination — songs may also carry
        // target_url but get their click-through from the in-app UI, not a
        // shade notification.
        if (!isAd || targetUrl.isEmpty()) {
            nm.cancel(AD_NOTIFICATION_ID);
            previousNotifiedTrackId = "";
            return;
        }

        if (trackId.equals(previousNotifiedTrackId)) return;

        ensureNotificationChannel(ctx, nm);
        nm.cancel(AD_NOTIFICATION_ID);
        previousNotifiedTrackId = trackId;

        // Tap → ClickLink endpoint via system browser. The backend records
        // the click against (track, asset, campaign) then 302-redirects to
        // the asset's landing page.
        Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse(targetUrl));
        view.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent contentPi = PendingIntent.getActivity(
            ctx,
            2,
            view,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );

        Bitmap art = fetchBitmap(imageUrl);

        NotificationCompat.Builder builder = new NotificationCompat.Builder(ctx, AD_CHANNEL_ID)
            .setSmallIcon(R.drawable.media3_notification_small_icon)
            .setContentTitle(title.isEmpty() ? "Now playing" : title)
            .setContentText(artist)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPi)
            .setAutoCancel(true);

        if (art != null) {
            builder.setLargeIcon(art)
                .setStyle(new NotificationCompat.BigPictureStyle()
                    .bigPicture(art)
                    .bigLargeIcon((Bitmap) null));
        }

        nm.notify(AD_NOTIFICATION_ID, builder.build());
        Log.i(TAG, "syncTrackNotification: posted for trackId=" + trackId
            + " withArt=" + (art != null));
    }

    private Bitmap fetchBitmap(String url) {
        if (url == null || url.isEmpty()) return null;
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null;
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestProperty("Accept", "image/*");
            try (InputStream in = conn.getInputStream()) {
                return BitmapFactory.decodeStream(in);
            }
        } catch (Exception ex) {
            Log.w(TAG, "fetchBitmap failed for " + url + ": " + ex.getMessage());
            return null;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private void clearTrackNotification() {
        Context ctx = notificationContext();
        if (ctx == null) return;
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(AD_NOTIFICATION_ID);
        previousNotifiedTrackId = "";
    }

    private static class UpcomingMetadataItem {
        final long fromUs;
        final long toUs;
        final String id;
        final String artist;
        final String title;
        final String album;
        final String imageUrl;
        final boolean maySkip;
        final boolean isAd;
        final String targetUrl;

        UpcomingMetadataItem(long fromUs, long toUs, String id, String artist, String title,
                             String album, String imageUrl, boolean maySkip, boolean isAd,
                             String targetUrl) {
            this.fromUs = fromUs;
            this.toUs = toUs;
            this.id = id;
            this.artist = artist;
            this.title = title;
            this.album = album;
            this.imageUrl = imageUrl;
            this.maySkip = maySkip;
            this.isAd = isAd;
            this.targetUrl = targetUrl;
        }

        static UpcomingMetadataItem fromJson(JSONObject obj) {
            return new UpcomingMetadataItem(
                obj.optLong("from_us", 0),
                obj.optLong("to_us", 0),
                obj.optString("id", ""),
                obj.optString("artist", ""),
                obj.optString("title", ""),
                obj.optString("album", ""),
                obj.optString("image_url", ""),
                obj.optBoolean("may_skip", true),
                obj.optBoolean("is_ad", false),
                obj.optString("target_url", "")
            );
        }
    }
}
