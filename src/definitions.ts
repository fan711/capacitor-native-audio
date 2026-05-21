export interface AudioPlayerDefaultParams {
    /**
     * Any string to differentiate different audio files.
     *
     * @since 1.0.0
     */
    audioId: string;
}

export interface AudioPlayerPrepareParams extends AudioPlayerDefaultParams {
    /**
     * Soundz-good base URL for this listener, e.g.
     * `https://stream.example/streams/app/{channelId}/{clientId}`. The plugin
     * derives every URL it needs from this base:
     *
     *   - `${streamBaseUrl}/stream` — the audio stream
     *   - `${streamBaseUrl}/metadata-upcoming` — upcoming-window metadata polling
     *   - `${streamBaseUrl}/vote/{trackId}` — thumbs up/down
     *   - `${streamBaseUrl}/skip/{trackId}` — skip current track
     *
     * @since 4.0.0
     */
    streamBaseUrl: string;

    /**
     * Whether to use this audio file for the notification.
     * This is considered the primary audio to play.
     *
     * It must be created first and you may only have one at a time.
     *
     * @default false
     * @since 1.0.0
     */
    useForNotification: boolean;

    /**
     * Is this audio for background music/audio.
     *
     * Should not be `true` when `useForNotification = true`.
     *
     * @default false
     * @since 1.0.0
     */
    isBackgroundMusic?: boolean;

    /**
     * Whether or not to loop other audio like background music
     * while the primary audio (`useForNotification = true`) is playing.
     *
     * @default false
     * @since 1.0.0
     */
    loop?: boolean;

    /**
     * Whether or not to show the seek backward button on the OS's notification.
     * Only has affect when `useForNotification = true`.
     *
     * @default true
     * @since 1.2.0
     */
    showSeekBackward?: boolean;

    /**
     * Whether or not to show the seek forward button on the OS's notification.
     * Only has affect when `useForNotification = true`.
     *
     * @default true
     * @since 1.2.0
     */
    showSeekForward?: boolean;

    /**
     * Time to seek backward in seconds on the OS's notification.
     * Only has affect when `showSeekBackward = true`.
     *
     * @default 5
     * @since 2.3.0
     */
    seekBackwardTime?: number;

    /**
     * Time to seek forward in seconds on the OS's notification.
     * Only has affect when `showSeekForward = true`.
     *
     * @default 5
     * @since 2.3.0
     */
    seekForwardTime?: number;
}

export interface AudioPlayerListenerParams {
    /**
     * The `audioId` set when `create` was called.
     *
     * @since 1.0.0
     */
    audioId: string;
}

export interface AudioPlayerListenerResult {
    callbackId: string;
}

/**
 * Track metadata payload mirroring the soundz-backend
 * `Broadcasts\CurrentTrack` WebSocket message. Returned by `getMetadata` and
 * consumed by the in-app UI alongside the WebSocket-driven live updates.
 */
export interface CurrentTrackEvent {
    channel_id: string;
    track: {
        id: string;
        artist: string;
        title: string;
        album: string;
        image_url: string;
        may_skip: boolean;
        is_ad: boolean;
        target_url: string;
    };
}

/**
 * One row of the upcoming-window response from soundz-good's
 * `/metadata-upcoming` endpoint. `from_us` / `to_us` are absolute UTC
 * microseconds at which the group starts / ends being heard; the plugin
 * applies metadata to the OS lockscreen locally at `from_us`.
 */
export interface UpcomingMetadataItem {
    from_us: number;
    to_us: number;
    id: string;
    artist: string;
    title: string;
    album: string;
    image_url: string;
    may_skip: boolean;
    is_ad: boolean;
    target_url: string;
}

export interface AudioPlayerPlugin {
    /**
     * Create an audio source to be played.
     *
     * @since 1.0.0
     */
    create(params: AudioPlayerPrepareParams): Promise<{ success: boolean }>;

    /**
     * Initialize the audio source. Prepares the audio to be played, buffers and such.
     *
     * Should be called after callbacks are registered (e.g. `onAudioReady`).
     *
     * @since 1.0.0
     */
    initialize(params: AudioPlayerDefaultParams): Promise<{ success: boolean }>;

    /**
     * Change the audio source on an existing audio source (`audioId`).
     *
     * This is useful for changing background music while the primary audio is playing
     * or changing the primary audio before it is playing to accommodate different durations
     * that a user can choose from.
     *
     * @since 1.0.0
     */
    changeAudioSource(params: AudioPlayerDefaultParams & { source: string }): Promise<void>;

    /**
     * Trigger a one-shot metadata refresh from the soundz-good /metadata
     * endpoint. The plugin updates its own state (OS now-playing, button
     * enable flags); the JS layer should use `getMetadata` to read the
     * result, since the plugin no longer pushes metadata events to JS.
     *
     * @since 2.2.0
     */
    updateMetadata(params: AudioPlayerDefaultParams): Promise<void>;

    /**
     * Get the duration of the audio source.
     *
     * Should be called once the audio is ready (`onAudioReady`).
     *
     * @since 1.0.0
     */
    getDuration(params: AudioPlayerDefaultParams): Promise<{ duration: number }>;

    /**
     * Get the current time of the audio source being played.
     *
     * @since 1.0.0
     */
    getCurrentTime(params: AudioPlayerDefaultParams): Promise<{ currentTime: number }>;

    /**
     * Play the audio source.
     *
     * @since 1.0.0
     */
    play(params: AudioPlayerDefaultParams): Promise<void>;

    /**
     * Pause the audio source.
     *
     * @since 1.0.0
     */
    pause(params: AudioPlayerDefaultParams): Promise<void>;

    /**
     * Seek the audio source to a specific time.
     *
     * @since 1.0.0
     */
    seek(params: AudioPlayerDefaultParams & { timeInSeconds: number }): Promise<void>;

    /**
     * Stop playing the audio source and reset the current time to zero.
     *
     * @since 1.0.0
     */
    stop(params: AudioPlayerDefaultParams): Promise<void>;

    /**
     * Set the volume of the audio source. Should be a decimal less than or equal to `1.00`.
     *
     * This is useful for background music.
     *
     * @since 1.0.0
     */
    setVolume(params: AudioPlayerDefaultParams & { volume: number }): Promise<void>;

    /**
     * Set the rate for the audio source to be played at.
     * Should be a decimal. An example being `1` is normal speed, `0.5` being half the speed and `1.5` being 1.5 times faster.
     *
     * @since 1.0.0
     */
    setRate(params: AudioPlayerDefaultParams & { rate: number }): Promise<void>;

    /**
     * Wether or not the audio source is currently playing.
     *
     * @since 1.0.0
     */
    isPlaying(params: AudioPlayerDefaultParams): Promise<{ isPlaying: boolean }>;

    /**
     * Get the current track metadata for the audio source. Shape mirrors
     * the soundz-backend `Broadcasts\CurrentTrack` WebSocket payload, so
     * the in-app UI can route this and the WebSocket message through one
     * handler.
     *
     * @since 3.1.0
     */
    getMetadata(params: AudioPlayerDefaultParams): Promise<CurrentTrackEvent>;

    /**
     * Destroy all resources for the audio source.
     * The audio source with `useForNotification = true` must be destroyed last.
     *
     * @since 1.0.0
     */
    destroy(params: AudioPlayerDefaultParams): Promise<void>;

    /**
     * Register a callback for when the app comes to the foreground.
     *
     * @since 1.0.0
     */
    onAppGainsFocus(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult>;

    /**
     * Registers a callback from when the app goes to the background.
     *
     * @since 1.0.0
     */
    onAppLosesFocus(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult>;

    /**
     * Registers a callback for when the audio source is ready to be played.
     *
     * @since 1.0.0
     */
    onAudioReady(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult>;

    /**
     * Registers a callback for when the audio source has ended (reached the end of the audio).
     *
     * @since 1.0.0
     */
    onAudioEnd(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult>;

    /**
     * Registers a callback for when state of playback for the audio source has changed by external controls.
     * This should be used to update your UI when the notification/external controls are used to control the playback.
     *
     * On Android, this also gets fired when your app changes the state (e.g. by calling `play`, `pause` or `stop`)
     * due to a limitation of not knowing where the state change came from, either the app or the `MediaSession` (external controls).
     *
     * It may be fixed in the future for Android if a solution is found so don't rely on it when your app itself changes the state.
     *
     * @since 1.0.0
     */
    onPlaybackStatusChange(
        params: AudioPlayerListenerParams,
        callback: (result: { status: 'playing' | 'paused' | 'stopped' }) => void,
    ): Promise<AudioPlayerListenerResult>;
}
