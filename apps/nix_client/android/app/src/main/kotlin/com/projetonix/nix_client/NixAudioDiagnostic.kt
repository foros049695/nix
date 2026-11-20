package com.projetonix.nix_client

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.max

internal class NixAudioDiagnostic(private val activity: Activity) {
    private val permissionRequest = 15203
    private var permissionResult: MethodChannel.Result? = null
    private var capture: Capture? = null

    private class Capture(val recorder: AudioRecord) {
        val running = AtomicBoolean(true)
        val peak = AtomicInteger(-1)

        val worker = Thread({
            try {
                val samples = ShortArray(1024)
                while (running.get()) {
                    val read = recorder.read(samples, 0, samples.size)
                    if (read <= 0) break
                    var level = 0
                    for (index in 0 until read) {
                        level = max(level, abs(samples[index].toInt()))
                    }
                    peak.accumulateAndGet(level) { old, sample -> max(old, sample) }
                }
                samples.fill(0)
            } finally {
                running.set(false)
                closeRecorder()
            }
        }, "nix-audio-diagnostic")

        @Synchronized
        private fun closeRecorder() {
            runCatching { recorder.stop() }
            recorder.release()
        }

        @Synchronized
        fun stop() {
            if (running.getAndSet(false)) runCatching { recorder.stop() }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> {
                val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val inputs = manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                    .map { it.productName.toString() }.distinct().joinToString()
                val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .map { it.productName.toString() }.distinct().joinToString()
                result.success("Entradas: ${inputs.ifEmpty { "nenhuma" }}\n" +
                    "Saídas: ${outputs.ifEmpty { "nenhuma" }}")
            }
            "start" -> {
                if (permissionResult != null || capture != null) {
                    result.error("MIC_BUSY", "Já existe um teste de microfone.", null)
                } else if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                    != PackageManager.PERMISSION_GRANTED) {
                    permissionResult = result
                    activity.requestPermissions(
                        arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequest
                    )
                } else {
                    start(result)
                }
            }
            "level" -> {
                val active = capture
                if (active == null || !active.running.get()) {
                    result.error("MIC_STOPPED", "A captura de microfone encerrou.", null)
                } else {
                    val peak = active.peak.getAndSet(-1)
                    result.success(if (peak < 0) null else peak / 32768.0)
                }
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != permissionRequest) return false
        val result = permissionResult ?: return true
        permissionResult = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            start(result)
        } else {
            result.error("MIC_PERMISSION", "Permita o acesso ao microfone para iniciar o teste.", null)
        }
        return true
    }

    @SuppressLint("MissingPermission")
    private fun start(result: MethodChannel.Result) {
        var recorder: AudioRecord? = null
        try {
            val rate = 16000
            val channel = AudioFormat.CHANNEL_IN_MONO
            val encoding = AudioFormat.ENCODING_PCM_16BIT
            val size = AudioRecord.getMinBufferSize(rate, channel, encoding)
            check(size > 0)
            val input = AudioRecord(MediaRecorder.AudioSource.MIC, rate, channel,
                encoding, max(size, 4096))
            recorder = input
            check(input.state == AudioRecord.STATE_INITIALIZED)
            input.startRecording()
            check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            val active = Capture(input)
            active.worker.start()
            capture = active
            result.success(null)
        } catch (_: Exception) {
            recorder?.release()
            result.error("MIC_UNAVAILABLE", "Não foi possível capturar áudio do microfone.", null)
        }
    }

    fun stop() {
        permissionResult?.error("MIC_CANCELLED", "Teste de microfone cancelado.", null)
        permissionResult = null
        capture?.stop()
        capture = null
    }
}
