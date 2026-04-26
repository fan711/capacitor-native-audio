enum AudioPlayerError: Error {
    case invalidAudioId
    case invalidPath
    case invalidSeekTime
    case invalidVolume
    case invalidRate
    case invalidSource
    case missingAudioSource
    case sourceAlreadyExists
    case runtimeError(String)
}
