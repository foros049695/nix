package com.projetonix.nix_client

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

internal class NixVoiceNotes(private val activity: Activity) {
    private companion object {
        const val permissionRequest = 15206
        const val sampleRate = 16000
        const val byteLimit = sampleRate * 2 * 12
    }

    private val handler = Handler(Looper.getMainLooper())
    private val pcm = ByteArray(byteLimit)
    private val samples = ShortArray(2048)
    private var length = 0
    private var peak = 0
    private var recorder: AudioRecord? = null
    private var player: AudioTrack? = null
    private var permissionReply: MethodChannel.Result? = null
    private var captureState = "idle"

    private val capture = object : Runnable {
        override fun run() {
            val input = recorder ?: return
            val count = input.read(samples, 0, minOf(samples.size, (pcm.size - length) / 2),
                AudioRecord.READ_NON_BLOCKING)
            if (count < 0) {
                clearRecording()
                captureState = "failed"
                return
            }
            for (index in 0 until count) {
                val sample = samples[index].toInt()
                pcm[length++] = sample.toByte()
                pcm[length++] = (sample shr 8).toByte()
                peak = maxOf(peak, abs(sample))
            }
            if (length < pcm.size) {
                handler.postDelayed(this, 25L)
            } else {
                releaseRecorder()
                captureState = "full"
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> requestStart(result)
                "status" -> {
                    result.success(mapOf("state" to captureState, "samples" to length / 2,
                        "peak" to peak))
                    peak = 0
                }
                "pause" -> {
                    check(captureState == "recording")
                    releaseRecorder()
                    captureState = "paused"
                    result.success(null)
                }
                "resume" -> {
                    check(captureState == "paused")
                    openRecorder()
                    result.success(null)
                }
                "finish" -> {
                    check(captureState in listOf("recording", "paused", "full") && length > 0)
                    val audio = pcm.copyOf(length)
                    clearRecording()
                    result.success(audio)
                }
                "play" -> {
                    play(requireNotNull(call.arguments as? ByteArray))
                    result.success(null)
                }
                "playing" -> result.success(player != null)
                "stopPlayback" -> {
                    releasePlayer()
                    result.success(null)
                }
                "cancel" -> {
                    stopAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("VOICE_AUDIO", "Não foi possível concluir a operação de áudio.", null)
        }
    }

    private fun requestStart(result: MethodChannel.Result) {
        check(permissionReply == null)
        clearRecording()
        releasePlayer()
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED) {
            openRecorder()
            result.success(null)
        } else {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequest)
            permissionReply = result
        }
    }

    fun onPermissionResult(code: Int, grants: IntArray): Boolean {
        if (code != permissionRequest) return false
        val result = permissionReply ?: return true
        permissionReply = null
        if (grants.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            result.error("VOICE_PERMISSION", "Autorize o acesso ao microfone para gravar.", null)
        } else {
            try {
                openRecorder()
                result.success(null)
            } catch (_: Exception) {
                result.error("VOICE_AUDIO", "O microfone está indisponível.", null)
            }
        }
        return true
    }

    @SuppressLint("MissingPermission")
    private fun openRecorder() {
        val channel = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minimum = AudioRecord.getMinBufferSize(sampleRate, channel, encoding)
        check(minimum > 0)
        val input = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channel,
            encoding, maxOf(8192, minimum))
        try {
            check(input.state == AudioRecord.STATE_INITIALIZED)
            input.startRecording()
            check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            recorder = input
            captureState = "recording"
            handler.post(capture)
        } catch (error: Exception) {
            input.release()
            throw error
        }
    }

    private fun play(bytes: ByteArray) {
        require(bytes.size in 2..byteLimit && bytes.size % 2 == 0)
        releasePlayer()
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(bytes.size)
            .build()
        player = track
        try {
            val decoded = ShortArray(bytes.size / 2)
            ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(decoded)
            try {
                check(track.write(decoded, 0, decoded.size) == decoded.size)
            } finally {
                decoded.fill(0)
            }
            track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
                override fun onMarkerReached(reached: AudioTrack) {
                    if (player === reached) releasePlayer()
                }
                override fun onPeriodicNotification(active: AudioTrack) = Unit
            }, handler)
            check(track.setNotificationMarkerPosition(bytes.size / 2) == AudioTrack.SUCCESS)
            track.play()
            check(track.playState == AudioTrack.PLAYSTATE_PLAYING)
        } catch (error: Exception) {
            releasePlayer()
            throw error
        }
    }

    private fun releaseRecorder() {
        handler.removeCallbacks(capture)
        recorder?.let {
            runCatching { it.stop() }
            it.release()
        }
        recorder = null
    }

    private fun clearRecording() {
        releaseRecorder()
        pcm.fill(0)
        samples.fill(0)
        length = 0
        peak = 0
        captureState = "idle"
    }

    private fun releasePlayer() {
        player?.let {
            runCatching { it.stop() }
            it.release()
        }
        player = null
    }

    fun stopAll() {
        permissionReply?.error("VOICE_CANCELLED", "Gravação cancelada.", null)
        permissionReply = null
        clearRecording()
        releasePlayer()
    }
}
