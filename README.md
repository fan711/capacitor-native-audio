# @mediagrid/capacitor-native-audio

## Description

Play audio in a Capacitor app natively (Android/iOS) from a URL/web source simultaneously with background audio. Also supports background playing with an OS notification.

## Install

### For Capacitor 8

```bash
npm install @mediagrid/capacitor-native-audio
npx cap sync
```

### For Capacitor 7

```bash
npm install @mediagrid/capacitor-native-audio@^2.0.0
npx cap sync
```

## Android

### `AndroidManifest.xml` required changes

Located at `android/app/src/main/AndroidManifest.xml`

```xml
<application>
    <!-- OTHER STUFF -->

    <!-- Add service to be used for background play -->
    <service
        android:name="us.mediagrid.capacitorjs.plugins.nativeaudio.AudioPlayerService"
        android:description="@string/audio_player_service_description"
        android:foregroundServiceType="mediaPlayback"
        android:exported="true">
        <intent-filter>
            <action android:name="androidx.media3.session.MediaSessionService"/>
        </intent-filter>
    </service>

    <!-- OTHER STUFF -->
</application>

<!-- Add required permissions -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### `strings.xml` required changes

Located at `android/app/src/main/res/values/strings.xml`

```xml
<resources>
    <!-- OTHER STUFF -->

    <!-- Describes the service in your app settings once installed -->
    <string name="audio_player_service_description">Allows for audio to play in the background.</string>
</resources>
```

# iOS

## Enable Audio Background Mode

This can be done in XCode or by editing `Info.plist` directly.

```xml
<!-- ios/App/App/Info.plist -->

<dict>
    <!-- OTHER STUFF -->

    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
    </array>

    <!-- OTHER STUFF -->
</dict>
```

## Add Now Playing Icon (optional) - DEPRECATED

⚠️⚠️ This is DEPRECATED. Use `artworkSource` now. ⚠️⚠️

If you would like a now playing icon to show in the iOS notification, add an image with the name `NowPlayingIcon` to your Asset catalog. See [Managing assets with asset catalogs](https://developer.apple.com/documentation/xcode/managing-assets-with-asset-catalogs) on how to add a new asset.

A PNG is recommended with the size of 1024 x 1024px. The same image can be used for the three different Asset wells (1x, 2x, 3x).

# Metadata Updates

This plugin supports playing audio streams and in order to update the metadata in the native OS notification, there is the ability for this plugin to fetch metadata from a specified URL at a set interval.

The URL shall return a JSON response with the following format:

```json
{
    "album_title": "My Album Title",
    "artist_name": "My Artist Name",
    "song_title": "My Song Title",
    "artwork_source": "https://example.com/example_artwork.png"
}
```

The update interval starts when the audio is played or un-paused and stops when paused, stopped or the audio ends.

# API

<docgen-index>

* [`create(...)`](#create)
* [`initialize(...)`](#initialize)
* [`changeAudioSource(...)`](#changeaudiosource)
* [`updateMetadata(...)`](#updatemetadata)
* [`getDuration(...)`](#getduration)
* [`getCurrentTime(...)`](#getcurrenttime)
* [`play(...)`](#play)
* [`pause(...)`](#pause)
* [`seek(...)`](#seek)
* [`setEpisodeTimeline(...)`](#setepisodetimeline)
* [`stop(...)`](#stop)
* [`setVolume(...)`](#setvolume)
* [`setRate(...)`](#setrate)
* [`isPlaying(...)`](#isplaying)
* [`getMetadata(...)`](#getmetadata)
* [`openOutputPicker()`](#openoutputpicker)
* [`destroy(...)`](#destroy)
* [`onAppGainsFocus(...)`](#onappgainsfocus)
* [`onAppLosesFocus(...)`](#onapplosesfocus)
* [`onAudioReady(...)`](#onaudioready)
* [`onAudioEnd(...)`](#onaudioend)
* [`onPlaybackStatusChange(...)`](#onplaybackstatuschange)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### create(...)

```typescript
create(params: AudioPlayerPrepareParams) => Promise<{ success: boolean; }>
```

Create an audio source to be played.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerprepareparams">AudioPlayerPrepareParams</a></code> |

**Returns:** <code>Promise&lt;{ success: boolean; }&gt;</code>

**Since:** 1.0.0

--------------------


### initialize(...)

```typescript
initialize(params: AudioPlayerDefaultParams) => Promise<{ success: boolean; }>
```

Initialize the audio source. Prepares the audio to be played, buffers and such.

Should be called after callbacks are registered (e.g. `onAudioReady`).

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Returns:** <code>Promise&lt;{ success: boolean; }&gt;</code>

**Since:** 1.0.0

--------------------


### changeAudioSource(...)

```typescript
changeAudioSource(params: AudioPlayerDefaultParams & { source: string; }) => Promise<void>
```

Change the audio source on an existing audio source (`audioId`).

This is useful for changing background music while the primary audio is playing
or changing the primary audio before it is playing to accommodate different durations
that a user can choose from.

| Param        | Type                                                                                                |
| ------------ | --------------------------------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a> & { source: string; }</code> |

**Since:** 1.0.0

--------------------


### updateMetadata(...)

```typescript
updateMetadata(params: AudioPlayerDefaultParams) => Promise<void>
```

Trigger a one-shot metadata refresh from the soundz-good /metadata
endpoint. The plugin updates its own state (OS now-playing, button
enable flags); the JS layer should use `getMetadata` to read the
result, since the plugin no longer pushes metadata events to JS.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Since:** 2.2.0

--------------------


### getDuration(...)

```typescript
getDuration(params: AudioPlayerDefaultParams) => Promise<{ duration: number; }>
```

Get the duration of the audio source.

Should be called once the audio is ready (`onAudioReady`).

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Returns:** <code>Promise&lt;{ duration: number; }&gt;</code>

**Since:** 1.0.0

--------------------


### getCurrentTime(...)

```typescript
getCurrentTime(params: AudioPlayerDefaultParams) => Promise<{ currentTime: number; }>
```

Get the current time of the audio source being played.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Returns:** <code>Promise&lt;{ currentTime: number; }&gt;</code>

**Since:** 1.0.0

--------------------


### play(...)

```typescript
play(params: AudioPlayerDefaultParams) => Promise<void>
```

Play the audio source.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Since:** 1.0.0

--------------------


### pause(...)

```typescript
pause(params: AudioPlayerDefaultParams) => Promise<void>
```

Pause the audio source.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Since:** 1.0.0

--------------------


### seek(...)

```typescript
seek(params: AudioPlayerDefaultParams & { timeInSeconds: number; }) => Promise<void>
```

Seek the audio source to a specific time.

| Param        | Type                                                                                                       |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a> & { timeInSeconds: number; }</code> |

**Since:** 1.0.0

--------------------


### setEpisodeTimeline(...)

```typescript
setEpisodeTimeline(params: AudioPlayerDefaultParams & { items: Array<{ sequence: number; track_id: string; time_start_us: number; time_end_us: number; title: string; artist: string; image_url: string; is_ad: boolean; target_url: string; }>; }) => Promise<void>
```

Hand the plugin the full on-demand episode timeline so the OS
lockscreen / Control Center metadata can be driven locally from the
audio position — without HTTP polling. When the active timeline item
changes (audio position crosses `time_end_us`), the plugin updates the
notification metadata directly.

Pass an empty `items` array to clear the timeline (e.g. on switching
back to a live channel) — the plugin then resumes its default behaviour
(polling the metadata-upcoming endpoint).

| Param        | Type                                                                                                                                                                                                                                                                    |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a> & { items: { sequence: number; track_id: string; time_start_us: number; time_end_us: number; title: string; artist: string; image_url: string; is_ad: boolean; target_url: string; }[]; }</code> |

--------------------


### stop(...)

```typescript
stop(params: AudioPlayerDefaultParams) => Promise<void>
```

Stop playing the audio source and reset the current time to zero.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Since:** 1.0.0

--------------------


### setVolume(...)

```typescript
setVolume(params: AudioPlayerDefaultParams & { volume: number; }) => Promise<void>
```

Set the volume of the audio source. Should be a decimal less than or equal to `1.00`.

This is useful for background music.

| Param        | Type                                                                                                |
| ------------ | --------------------------------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a> & { volume: number; }</code> |

**Since:** 1.0.0

--------------------


### setRate(...)

```typescript
setRate(params: AudioPlayerDefaultParams & { rate: number; }) => Promise<void>
```

Set the rate for the audio source to be played at.
Should be a decimal. An example being `1` is normal speed, `0.5` being half the speed and `1.5` being 1.5 times faster.

| Param        | Type                                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a> & { rate: number; }</code> |

**Since:** 1.0.0

--------------------


### isPlaying(...)

```typescript
isPlaying(params: AudioPlayerDefaultParams) => Promise<{ isPlaying: boolean; }>
```

Wether or not the audio source is currently playing.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Returns:** <code>Promise&lt;{ isPlaying: boolean; }&gt;</code>

**Since:** 1.0.0

--------------------


### getMetadata(...)

```typescript
getMetadata(params: AudioPlayerDefaultParams) => Promise<CurrentTrackEvent>
```

Get the current track metadata for the audio source. Shape mirrors
the soundz-backend `Broadcasts\CurrentTrack` WebSocket payload, so
the in-app UI can route this and the WebSocket message through one
handler.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Returns:** <code>Promise&lt;<a href="#currenttrackevent">CurrentTrackEvent</a>&gt;</code>

**Since:** 3.1.0

--------------------


### openOutputPicker()

```typescript
openOutputPicker() => Promise<void>
```

Open the OS native audio-output picker so the listener can route
playback to an external device. On iOS this is the AirPlay route
picker; on Android the system Media Output switcher (Bluetooth,
speaker, cast). Acts on the shared/global audio route, so it takes
no `audioId`. No-op on web.

**Since:** 4.1.0

--------------------


### destroy(...)

```typescript
destroy(params: AudioPlayerDefaultParams) => Promise<void>
```

Destroy all resources for the audio source.
The audio source with `useForNotification = true` must be destroyed last.

| Param        | Type                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **`params`** | <code><a href="#audioplayerdefaultparams">AudioPlayerDefaultParams</a></code> |

**Since:** 1.0.0

--------------------


### onAppGainsFocus(...)

```typescript
onAppGainsFocus(params: AudioPlayerListenerParams, callback: () => void) => Promise<AudioPlayerListenerResult>
```

Register a callback for when the app comes to the foreground.

| Param          | Type                                                                            |
| -------------- | ------------------------------------------------------------------------------- |
| **`params`**   | <code><a href="#audioplayerlistenerparams">AudioPlayerListenerParams</a></code> |
| **`callback`** | <code>() =&gt; void</code>                                                      |

**Returns:** <code>Promise&lt;<a href="#audioplayerlistenerresult">AudioPlayerListenerResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### onAppLosesFocus(...)

```typescript
onAppLosesFocus(params: AudioPlayerListenerParams, callback: () => void) => Promise<AudioPlayerListenerResult>
```

Registers a callback from when the app goes to the background.

| Param          | Type                                                                            |
| -------------- | ------------------------------------------------------------------------------- |
| **`params`**   | <code><a href="#audioplayerlistenerparams">AudioPlayerListenerParams</a></code> |
| **`callback`** | <code>() =&gt; void</code>                                                      |

**Returns:** <code>Promise&lt;<a href="#audioplayerlistenerresult">AudioPlayerListenerResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### onAudioReady(...)

```typescript
onAudioReady(params: AudioPlayerListenerParams, callback: () => void) => Promise<AudioPlayerListenerResult>
```

Registers a callback for when the audio source is ready to be played.

| Param          | Type                                                                            |
| -------------- | ------------------------------------------------------------------------------- |
| **`params`**   | <code><a href="#audioplayerlistenerparams">AudioPlayerListenerParams</a></code> |
| **`callback`** | <code>() =&gt; void</code>                                                      |

**Returns:** <code>Promise&lt;<a href="#audioplayerlistenerresult">AudioPlayerListenerResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### onAudioEnd(...)

```typescript
onAudioEnd(params: AudioPlayerListenerParams, callback: () => void) => Promise<AudioPlayerListenerResult>
```

Registers a callback for when the audio source has ended (reached the end of the audio).

| Param          | Type                                                                            |
| -------------- | ------------------------------------------------------------------------------- |
| **`params`**   | <code><a href="#audioplayerlistenerparams">AudioPlayerListenerParams</a></code> |
| **`callback`** | <code>() =&gt; void</code>                                                      |

**Returns:** <code>Promise&lt;<a href="#audioplayerlistenerresult">AudioPlayerListenerResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### onPlaybackStatusChange(...)

```typescript
onPlaybackStatusChange(params: AudioPlayerListenerParams, callback: (result: { status: 'playing' | 'paused' | 'stopped'; }) => void) => Promise<AudioPlayerListenerResult>
```

Registers a callback for when state of playback for the audio source has changed by external controls.
This should be used to update your UI when the notification/external controls are used to control the playback.

On Android, this also gets fired when your app changes the state (e.g. by calling `play`, `pause` or `stop`)
due to a limitation of not knowing where the state change came from, either the app or the `MediaSession` (external controls).

It may be fixed in the future for Android if a solution is found so don't rely on it when your app itself changes the state.

| Param          | Type                                                                              |
| -------------- | --------------------------------------------------------------------------------- |
| **`params`**   | <code><a href="#audioplayerlistenerparams">AudioPlayerListenerParams</a></code>   |
| **`callback`** | <code>(result: { status: 'playing' \| 'paused' \| 'stopped'; }) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#audioplayerlistenerresult">AudioPlayerListenerResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### Interfaces


#### AudioPlayerPrepareParams

| Prop                     | Type                 | Description                                                                                                                                                                                                                                                                                                                                                                                            | Default            | Since |
| ------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------ | ----- |
| **`streamBaseUrl`**      | <code>string</code>  | Soundz-good base URL for this listener, e.g. `https://stream.example/streams/app/{channelId}/{clientId}`. The plugin derives every URL it needs from this base: - `${streamBaseUrl}/stream` — the audio stream - `${streamBaseUrl}/metadata-upcoming` — upcoming-window metadata polling - `${streamBaseUrl}/vote/{trackId}` — thumbs up/down - `${streamBaseUrl}/skip/{trackId}` — skip current track |                    | 4.0.0 |
| **`useForNotification`** | <code>boolean</code> | Whether to use this audio file for the notification. This is considered the primary audio to play. It must be created first and you may only have one at a time.                                                                                                                                                                                                                                       | <code>false</code> | 1.0.0 |
| **`isBackgroundMusic`**  | <code>boolean</code> | Is this audio for background music/audio. Should not be `true` when `useForNotification = true`.                                                                                                                                                                                                                                                                                                       | <code>false</code> | 1.0.0 |
| **`loop`**               | <code>boolean</code> | Whether or not to loop other audio like background music while the primary audio (`useForNotification = true`) is playing.                                                                                                                                                                                                                                                                             | <code>false</code> | 1.0.0 |
| **`showSeekBackward`**   | <code>boolean</code> | Whether or not to show the seek backward button on the OS's notification. Only has affect when `useForNotification = true`.                                                                                                                                                                                                                                                                            | <code>true</code>  | 1.2.0 |
| **`showSeekForward`**    | <code>boolean</code> | Whether or not to show the seek forward button on the OS's notification. Only has affect when `useForNotification = true`.                                                                                                                                                                                                                                                                             | <code>true</code>  | 1.2.0 |
| **`seekBackwardTime`**   | <code>number</code>  | Time to seek backward in seconds on the OS's notification. Only has affect when `showSeekBackward = true`.                                                                                                                                                                                                                                                                                             | <code>5</code>     | 2.3.0 |
| **`seekForwardTime`**    | <code>number</code>  | Time to seek forward in seconds on the OS's notification. Only has affect when `showSeekForward = true`.                                                                                                                                                                                                                                                                                               | <code>5</code>     | 2.3.0 |


#### AudioPlayerDefaultParams

| Prop          | Type                | Description                                        | Since |
| ------------- | ------------------- | -------------------------------------------------- | ----- |
| **`audioId`** | <code>string</code> | Any string to differentiate different audio files. | 1.0.0 |


#### Array

| Prop         | Type                | Description                                                                                            |
| ------------ | ------------------- | ------------------------------------------------------------------------------------------------------ |
| **`length`** | <code>number</code> | Gets or sets the length of the array. This is a number one higher than the highest index in the array. |

| Method             | Signature                                                                                                                     | Description                                                                                                                                                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **toString**       | () =&gt; string                                                                                                               | Returns a string representation of an array.                                                                                                                                                                                                |
| **toLocaleString** | () =&gt; string                                                                                                               | Returns a string representation of an array. The elements are converted to string using their toLocalString methods.                                                                                                                        |
| **pop**            | () =&gt; T \| undefined                                                                                                       | Removes the last element from an array and returns it. If the array is empty, undefined is returned and the array is not modified.                                                                                                          |
| **push**           | (...items: T[]) =&gt; number                                                                                                  | Appends new elements to the end of an array, and returns the new length of the array.                                                                                                                                                       |
| **concat**         | (...items: <a href="#concatarray">ConcatArray</a>&lt;T&gt;[]) =&gt; T[]                                                       | Combines two or more arrays. This method returns a new array without modifying any existing arrays.                                                                                                                                         |
| **concat**         | (...items: (T \| <a href="#concatarray">ConcatArray</a>&lt;T&gt;)[]) =&gt; T[]                                                | Combines two or more arrays. This method returns a new array without modifying any existing arrays.                                                                                                                                         |
| **join**           | (separator?: string \| undefined) =&gt; string                                                                                | Adds all the elements of an array into a string, separated by the specified separator string.                                                                                                                                               |
| **reverse**        | () =&gt; T[]                                                                                                                  | Reverses the elements in an array in place. This method mutates the array and returns a reference to the same array.                                                                                                                        |
| **shift**          | () =&gt; T \| undefined                                                                                                       | Removes the first element from an array and returns it. If the array is empty, undefined is returned and the array is not modified.                                                                                                         |
| **slice**          | (start?: number \| undefined, end?: number \| undefined) =&gt; T[]                                                            | Returns a copy of a section of an array. For both start and end, a negative index can be used to indicate an offset from the end of the array. For example, -2 refers to the second to last element of the array.                           |
| **sort**           | (compareFn?: ((a: T, b: T) =&gt; number) \| undefined) =&gt; this                                                             | Sorts an array in place. This method mutates the array and returns a reference to the same array.                                                                                                                                           |
| **splice**         | (start: number, deleteCount?: number \| undefined) =&gt; T[]                                                                  | Removes elements from an array and, if necessary, inserts new elements in their place, returning the deleted elements.                                                                                                                      |
| **splice**         | (start: number, deleteCount: number, ...items: T[]) =&gt; T[]                                                                 | Removes elements from an array and, if necessary, inserts new elements in their place, returning the deleted elements.                                                                                                                      |
| **unshift**        | (...items: T[]) =&gt; number                                                                                                  | Inserts new elements at the start of an array, and returns the new length of the array.                                                                                                                                                     |
| **indexOf**        | (searchElement: T, fromIndex?: number \| undefined) =&gt; number                                                              | Returns the index of the first occurrence of a value in an array, or -1 if it is not present.                                                                                                                                               |
| **lastIndexOf**    | (searchElement: T, fromIndex?: number \| undefined) =&gt; number                                                              | Returns the index of the last occurrence of a specified value in an array, or -1 if it is not present.                                                                                                                                      |
| **every**          | &lt;S extends T&gt;(predicate: (value: T, index: number, array: T[]) =&gt; value is S, thisArg?: any) =&gt; this is S[]       | Determines whether all the members of an array satisfy the specified test.                                                                                                                                                                  |
| **every**          | (predicate: (value: T, index: number, array: T[]) =&gt; unknown, thisArg?: any) =&gt; boolean                                 | Determines whether all the members of an array satisfy the specified test.                                                                                                                                                                  |
| **some**           | (predicate: (value: T, index: number, array: T[]) =&gt; unknown, thisArg?: any) =&gt; boolean                                 | Determines whether the specified callback function returns true for any element of an array.                                                                                                                                                |
| **forEach**        | (callbackfn: (value: T, index: number, array: T[]) =&gt; void, thisArg?: any) =&gt; void                                      | Performs the specified action for each element in an array.                                                                                                                                                                                 |
| **map**            | &lt;U&gt;(callbackfn: (value: T, index: number, array: T[]) =&gt; U, thisArg?: any) =&gt; U[]                                 | Calls a defined callback function on each element of an array, and returns an array that contains the results.                                                                                                                              |
| **filter**         | &lt;S extends T&gt;(predicate: (value: T, index: number, array: T[]) =&gt; value is S, thisArg?: any) =&gt; S[]               | Returns the elements of an array that meet the condition specified in a callback function.                                                                                                                                                  |
| **filter**         | (predicate: (value: T, index: number, array: T[]) =&gt; unknown, thisArg?: any) =&gt; T[]                                     | Returns the elements of an array that meet the condition specified in a callback function.                                                                                                                                                  |
| **reduce**         | (callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) =&gt; T) =&gt; T                           | Calls the specified callback function for all the elements in an array. The return value of the callback function is the accumulated result, and is provided as an argument in the next call to the callback function.                      |
| **reduce**         | (callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) =&gt; T, initialValue: T) =&gt; T          |                                                                                                                                                                                                                                             |
| **reduce**         | &lt;U&gt;(callbackfn: (previousValue: U, currentValue: T, currentIndex: number, array: T[]) =&gt; U, initialValue: U) =&gt; U | Calls the specified callback function for all the elements in an array. The return value of the callback function is the accumulated result, and is provided as an argument in the next call to the callback function.                      |
| **reduceRight**    | (callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) =&gt; T) =&gt; T                           | Calls the specified callback function for all the elements in an array, in descending order. The return value of the callback function is the accumulated result, and is provided as an argument in the next call to the callback function. |
| **reduceRight**    | (callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) =&gt; T, initialValue: T) =&gt; T          |                                                                                                                                                                                                                                             |
| **reduceRight**    | &lt;U&gt;(callbackfn: (previousValue: U, currentValue: T, currentIndex: number, array: T[]) =&gt; U, initialValue: U) =&gt; U | Calls the specified callback function for all the elements in an array, in descending order. The return value of the callback function is the accumulated result, and is provided as an argument in the next call to the callback function. |


#### ConcatArray

| Prop         | Type                |
| ------------ | ------------------- |
| **`length`** | <code>number</code> |

| Method    | Signature                                                          |
| --------- | ------------------------------------------------------------------ |
| **join**  | (separator?: string \| undefined) =&gt; string                     |
| **slice** | (start?: number \| undefined, end?: number \| undefined) =&gt; T[] |


#### CurrentTrackEvent

Track metadata payload mirroring the soundz-backend
`Broadcasts\CurrentTrack` WebSocket message. Returned by `getMetadata` and
consumed by the in-app UI alongside the WebSocket-driven live updates.

| Prop             | Type                                                                                                                                                 |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`channel_id`** | <code>string</code>                                                                                                                                  |
| **`track`**      | <code>{ id: string; artist: string; title: string; album: string; image_url: string; may_skip: boolean; is_ad: boolean; target_url: string; }</code> |


#### AudioPlayerListenerResult

| Prop             | Type                |
| ---------------- | ------------------- |
| **`callbackId`** | <code>string</code> |


#### AudioPlayerListenerParams

| Prop          | Type                | Description                                 | Since |
| ------------- | ------------------- | ------------------------------------------- | ----- |
| **`audioId`** | <code>string</code> | The `audioId` set when `create` was called. | 1.0.0 |

</docgen-api>
