package com.projetonix.nix_client

import android.app.Activity
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class NixPagerAudio(private val activity: Activity) {
    private val requestCode = 15205
    private val localProviders = setOf(
        "com.android.externalstorage.documents",
        "com.android.providers.media.documents",
    )
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingPlay: MethodChannel.Result? = null
    private var player: MediaPlayer? = null
    private var playingUri: Uri? = null
    private var pickerInFlight = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pick" -> pick(result)
                "play" -> play(localAudioUri(call.argument<String>("uri")), result)
                "playing" -> result.success(playingUri?.toString())
                "position" -> result.success(playbackSnapshot())
                "pause" -> {
                    val current = player
                    if (current == null || playingUri == null) {
                        result.error("PAGER_AUDIO_IDLE", "Nenhum áudio em reprodução.", null)
                    } else {
                        if (current.isPlaying) current.pause()
                        result.success(playbackSnapshot())
                    }
                }
                "resume" -> {
                    val current = player
                    if (current == null || playingUri == null) {
                        result.error("PAGER_AUDIO_IDLE", "Nenhum áudio preparado.", null)
                    } else {
                        current.start()
                        result.success(playbackSnapshot())
                    }
                }
                "seek" -> {
                    val current = player
                    if (current == null || playingUri == null) {
                        result.error("PAGER_AUDIO_IDLE", "Nenhum áudio preparado.", null)
                    } else {
                        val requested = call.argument<Int>("positionMs") ?: 0
                        current.seekTo(requested.coerceIn(0, current.duration.coerceAtLeast(0)))
                        result.success(playbackSnapshot())
                    }
                }
                "volume" -> {
                    val level = (call.argument<Double>("value") ?: 1.0).toFloat().coerceIn(0f, 1f)
                    player?.setVolume(level, level)
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "wipe" -> {
                    destroy()
                    activity.contentResolver.persistedUriPermissions.forEach {
                        if (it.uri.authority in localProviders && it.isReadPermission) {
                            releasePermission(it.uri)
                        }
                    }
                    result.success(null)
                }
                "release" -> {
                    val uri = localAudioUri(call.argument<String>("uri"))
                    if (uri == playingUri) stop()
                    releasePermission(uri)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("PAGER_AUDIO_ERROR", "Não foi possível acessar o áudio local.", null)
        }
    }

    private fun localAudioUri(value: String?): Uri {
        require(!value.isNullOrBlank() && value.length <= 2048)
        val uri = Uri.parse(value)
        require(uri.scheme == "content" && uri.authority in localProviders)
        return uri
    }

    private fun pick(result: MethodChannel.Result) {
        if (pickerInFlight) {
            result.error("PAGER_AUDIO_BUSY", "O seletor já está aberto.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "audio/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, requestCode)
        pendingPicker = result
        pickerInFlight = true
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        pickerInFlight = false
        val result = pendingPicker ?: return true
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        try {
            val uri = localAudioUri(data?.data?.toString())
            val resolver = activity.contentResolver
            require(resolver.getType(uri)?.startsWith("audio/") == true)
            val name = resolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { if (it.moveToFirst()) it.getString(0) else null }
            resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            result.success(mapOf("uri" to uri.toString(), "name" to (name ?: "Faixa").take(160)))
        } catch (_: Exception) {
            result.error(
                "PAGER_AUDIO_SOURCE", "Escolha um arquivo de áudio no armazenamento local.", null,
            )
        }
        return true
    }

    private fun play(uri: Uri, result: MethodChannel.Result) {
        stop()
        val next = MediaPlayer()
        player = next
        try {
            next.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build())
            val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r")
                ?: error("Arquivo indisponível.")
            descriptor.use { asset ->
                if (asset.declaredLength < 0) {
                    next.setDataSource(asset.fileDescriptor)
                } else {
                    next.setDataSource(asset.fileDescriptor, asset.startOffset, asset.declaredLength)
                }
            }
            next.setOnPreparedListener {
                if (player === next) {
                    try {
                        next.start()
                        playingUri = uri
                        pendingPlay = null
                        result.success(null)
                    } catch (_: Exception) {
                        stop("Não foi possível iniciar a reprodução.")
                    }
                }
            }
            next.setOnCompletionListener { if (player === next) stop() }
            next.setOnErrorListener { _, _, _ ->
                if (player === next) stop("O Android não conseguiu reproduzir o arquivo.")
                true
            }
            next.prepareAsync()
            pendingPlay = result
        } catch (_: Exception) {
            stop()
            result.error("PAGER_AUDIO_PLAY", "O arquivo está ausente ou é incompatível.", null)
        }
    }

    private fun playbackSnapshot(): Map<String, Any> {
        val current = player
        if (current == null || playingUri == null) {
            return mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0)
        }
        return mapOf(
            "isPlaying" to runCatching { current.isPlaying }.getOrDefault(false),
            "positionMs" to runCatching { current.currentPosition }.getOrDefault(0),
            "durationMs" to runCatching { current.duration }.getOrDefault(0),
        )
    }

    fun stop(message: String = "Reprodução interrompida.") {
        val active = player
        player = null
        playingUri = null
        active?.release()
        pendingPlay?.error("PAGER_AUDIO_STOP", message, null)
        pendingPlay = null
    }

    fun destroy() {
        stop()
        pendingPicker?.success(null)
        pendingPicker = null
    }

    private fun releasePermission(uri: Uri) {
        runCatching {
            activity.contentResolver.releasePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
    }
}
