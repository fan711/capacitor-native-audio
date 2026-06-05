import { WebPlugin } from '@capacitor/core';

import type {
    AudioPlayerDefaultParams,
    AudioPlayerListenerParams,
    AudioPlayerListenerResult,
    AudioPlayerPlugin,
    AudioPlayerPrepareParams,
    CurrentTrackEvent,
} from './definitions';

export class AudioPlayerWeb extends WebPlugin implements AudioPlayerPlugin {
    create(params: AudioPlayerPrepareParams): Promise<{ success: boolean }> {
        throw this.unimplemented('Not implemented on web.');
    }

    initialize(params: AudioPlayerDefaultParams): Promise<{ success: boolean }> {
        throw this.unimplemented('Not implemented on web.');
    }

    changeAudioSource(params: AudioPlayerDefaultParams & { source: string }): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    updateMetadata(params: AudioPlayerDefaultParams): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    getDuration(params: AudioPlayerDefaultParams): Promise<{ duration: number }> {
        throw this.unimplemented('Not implemented on web.');
    }

    getCurrentTime(params: AudioPlayerDefaultParams): Promise<{ currentTime: number }> {
        throw this.unimplemented('Not implemented on web.');
    }

    play(params: AudioPlayerDefaultParams): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    pause(params: AudioPlayerDefaultParams): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    seek(params: AudioPlayerDefaultParams & { timeInSeconds: number }): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    setEpisodeTimeline(_params: AudioPlayerDefaultParams & {
        items: Array<{
            sequence: number;
            track_id: string;
            time_start_us: number;
            time_end_us: number;
            title: string;
            artist: string;
            image_url: string;
            is_ad: boolean;
            target_url: string;
        }>;
    }): Promise<void> {
        // Web doesn't use this plugin for lockscreen metadata; the in-app
        // player drives the MediaSession directly.
        return Promise.resolve();
    }

    openOutputPicker(): Promise<void> {
        // Web routes output through the Audio Output Devices API in the app's
        // own player composable, not through this plugin.
        return Promise.resolve();
    }

    stop(params: AudioPlayerDefaultParams): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    setVolume(params: AudioPlayerDefaultParams & { volume: number }): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    setRate(params: AudioPlayerDefaultParams & { rate: number }): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    isPlaying(params: AudioPlayerDefaultParams): Promise<{ isPlaying: boolean }> {
        throw this.unimplemented('Not implemented on web.');
    }

    getMetadata(params: AudioPlayerDefaultParams): Promise<CurrentTrackEvent> {
        throw this.unimplemented('Not implemented on web.');
    }

    destroy(params: AudioPlayerDefaultParams): Promise<void> {
        throw this.unimplemented('Not implemented on web.');
    }

    onAppGainsFocus(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult> {
        throw this.unimplemented('Not implemented on web.');
    }

    onAppLosesFocus(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult> {
        throw this.unimplemented('Not implemented on web.');
    }

    onAudioReady(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult> {
        throw this.unimplemented('Not implemented on web.');
    }

    onAudioEnd(
        params: AudioPlayerListenerParams,
        callback: () => void,
    ): Promise<AudioPlayerListenerResult> {
        throw this.unimplemented('Not implemented on web.');
    }

    onPlaybackStatusChange(
        params: AudioPlayerListenerParams,
        callback: (result: { status: 'playing' | 'paused' | 'stopped' }) => void,
    ): Promise<AudioPlayerListenerResult> {
        throw this.unimplemented('Not implemented on web.');
    }
}
