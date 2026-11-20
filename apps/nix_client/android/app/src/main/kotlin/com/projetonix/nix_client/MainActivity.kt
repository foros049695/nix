package com.projetonix.nix_client

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import com.google.zxing.client.android.Intents
import com.journeyapps.barcodescanner.ScanIntentResult
import com.journeyapps.barcodescanner.ScanOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val keystoreChannelName = "com.projetonix.nix/keystore"
    private val platformChannelName = "com.projetonix.nix/platform"
    private val bleChannelName = "com.projetonix.nix/ble_mesh"
    private val loraChannelName = "com.projetonix.nix/lora_rnode"

    private val keyAlias = "nix_vault_kek_v1"
    private val prefsName = "nix_keystore_vault_prefs"

    private val invitationQrRequest = 15204
    private var invitationQrResult: MethodChannel.Result? = null

    private val localMediaRequest = 15201
    private var localMediaResult: MethodChannel.Result? = null

    private val attachmentRequest = 15202
    private var attachmentResult: MethodChannel.Result? = null
    private var attachmentExtensions: Set<String> = emptySet()

    private val audioDiagnostic by lazy { NixAudioDiagnostic(this) }
    private val voiceNotes by lazy { NixVoiceNotes(this) }
    private val pagerAudio by lazy { NixPagerAudio(this) }
    private var bleController: NixBleMeshController? = null
    private var rnodeController: NixRNodeRadioController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.projetonix.nix/audio_diagnostic")
            .setMethodCallHandler(audioDiagnostic::handle)

        MethodChannel(messenger, "com.projetonix.nix/voice_notes")
            .setMethodCallHandler(voiceNotes::handle)

        MethodChannel(messenger, "com.projetonix.nix/pager_audio")
            .setMethodCallHandler(pagerAudio::handle)

        MethodChannel(messenger, "com.projetonix.nix/invitation_qr")
            .setMethodCallHandler { call, result ->
                if (call.method != "scan") {
                    result.notImplemented()
                } else {
                    scanInvitationQr(result)
                }
            }

        // 1. Canal AndroidKeyStore TEE / StrongBox (AES-256-GCM)
        MethodChannel(messenger, keystoreChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "storeSecret" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key.isNullOrEmpty() || value == null) {
                            result.error("INVALID_ARGS", "key e value são obrigatórios", null)
                        } else {
                            storeEncryptedSecret(key, value)
                            result.success(true)
                        }
                    }
                    "readSecret" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "key obrigatório", null)
                        } else {
                            result.success(readEncryptedSecret(key))
                        }
                    }
                    "deleteSecret" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "key obrigatório", null)
                        } else {
                            getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                                .edit()
                                .remove(key)
                                .apply()
                            result.success(true)
                        }
                    }
                    "getKeystoreInfo" -> {
                        result.success(inspectKeystoreSecurityInfo())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("KEYSTORE_ERROR", e.message ?: "Erro AndroidKeyStore", null)
            }
        }

        // 2. Canal Runtime Nativo Android (filesDir, nativeLibraryDir/libtor.so, ABI, allowBackup)
        MethodChannel(messenger, platformChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickLocalAttachments" -> {
                    if (attachmentResult != null) {
                        result.error("ATTACHMENT_BUSY", "O seletor já está aberto.", null)
                    } else {
                        try {
                            val extensions = call.argument<List<String>>("extensions").orEmpty()
                                .map { it.lowercase() }.toSet()
                            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (extensions.isNotEmpty() &&
                                    extensions.all { it in setOf("png", "jpg", "jpeg", "webp", "gif") }
                                ) "image/*" else "*/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") == true)
                                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            }
                            attachmentResult = result
                            attachmentExtensions = extensions
                            startActivityForResult(picker, attachmentRequest)
                        } catch (_: Exception) {
                            attachmentResult = null
                            result.error("ATTACHMENT_PICKER", "Seletor de arquivos indisponível.", null)
                        }
                    }
                }
                "openLocalMedia" -> {
                    if (localMediaResult != null) {
                        result.error("MEDIA_BUSY", "O seletor de mídia já está aberto.", null)
                    } else {
                        try {
                            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*"))
                                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            }
                            localMediaResult = result
                            startActivityForResult(picker, localMediaRequest)
                        } catch (_: Exception) {
                            localMediaResult = null
                            result.error("MEDIA_PICKER", "Seletor de mídia indisponível.", null)
                        }
                    }
                }
                "getRuntimeInfo" -> {
                    val nativeLibDir = applicationInfo.nativeLibraryDir ?: ""
                    val torFile = File(nativeLibDir, "libtor.so")
                    val allowBackupFlag = (applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP) != 0
                    val primaryAbi = if (Build.SUPPORTED_ABIS.isNotEmpty()) Build.SUPPORTED_ABIS[0] else "unknown"
                    result.success(
                        mapOf(
                            "filesDir" to filesDir.absolutePath,
                            "cacheDir" to cacheDir.absolutePath,
                            "nativeLibraryDir" to nativeLibDir,
                            "torBinaryPath" to torFile.absolutePath,
                            "torBinaryExists" to torFile.exists(),
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "primaryAbi" to primaryAbi,
                            "allowBackupDisabled" to !allowBackupFlag
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }

        // 3. Canal Bluetooth LE Mesh Físico (GATT Server + Client + Scanner + Advertiser)
        val bleCh = MethodChannel(messenger, bleChannelName)
        bleController = NixBleMeshController(this, bleCh)
        bleCh.setMethodCallHandler { call, result ->
            bleController?.handleMethodCall(call, result)
        }

        // 4. Canal Rádio LoRa / Reticulum RNode (USB-OTG & BLE Nordic UART KISS)
        val loraCh = MethodChannel(messenger, loraChannelName)
        rnodeController = NixRNodeRadioController(this, loraCh)
        loraCh.setMethodCallHandler { call, result ->
            rnodeController?.handleMethodCall(call, result)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (voiceNotes.onPermissionResult(requestCode, grantResults)) return
        if (audioDiagnostic.onPermissionResult(requestCode, grantResults)) return
        if (bleController?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun scanInvitationQr(result: MethodChannel.Result) {
        if (invitationQrResult != null) {
            result.error("QR_BUSY", "O leitor já está aberto.", null)
            return
        }
        invitationQrResult = result
        try {
            val options = ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("Aponte a câmera para o convite do Nix")
                .setBeepEnabled(false)
                .setBarcodeImageEnabled(false)
                .setOrientationLocked(false)
            startActivityForResult(options.createScanIntent(this), invitationQrRequest)
        } catch (_: Exception) {
            invitationQrResult = null
            result.error("CAMERA_UNAVAILABLE", "Não foi possível abrir a câmera.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (pagerAudio.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode == invitationQrRequest) {
            val pending = invitationQrResult ?: return
            invitationQrResult = null
            val scan = ScanIntentResult.parseActivityResult(resultCode, data)
            if (scan.originalIntent?.getBooleanExtra(
                    Intents.Scan.MISSING_CAMERA_PERMISSION, false
                ) == true) {
                pending.error("CAMERA_DENIED", "Autorize o acesso à câmera para ler o convite.", null)
            } else {
                pending.success(scan.contents)
            }
            return
        }
        if (requestCode == attachmentRequest) {
            readSelectedAttachments(resultCode, data)
            return
        }
        if (requestCode != localMediaRequest) return
        val result = localMediaResult ?: return
        localMediaResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        try {
            val uri = data?.data
            val mime = uri?.let { contentResolver.getType(it) }
            if (uri?.scheme != "content" ||
                mime == null || (!mime.startsWith("audio/") && !mime.startsWith("video/"))
            ) {
                result.error("MEDIA_TYPE", "Selecione um arquivo de áudio ou vídeo.", null)
                return
            }
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(view, "Abrir mídia local"))
            result.success(null)
        } catch (_: Exception) {
            result.error("MEDIA_PLAYER", "Player indisponível.", null)
        }
    }

    private fun readSelectedAttachments(resultCode: Int, data: Intent?) {
        val result = attachmentResult ?: return
        attachmentResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }
        val extensions = attachmentExtensions
        val selection = data.clipData
        val files = if (selection != null) {
            if (selection.itemCount > 8) {
                result.error("ATTACHMENT_LIMIT", "Selecione no máximo oito arquivos.", null)
                return
            }
            (0 until selection.itemCount).mapNotNull { selection.getItemAt(it).uri }
        } else {
            listOfNotNull(data.data)
        }

        Thread {
            val imports = File(filesDir, "nix_attachment_imports")
            val batch = File(imports, java.util.UUID.randomUUID().toString())
            try {
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
                imports.listFiles()?.filter { it.lastModified() < cutoff }
                    ?.forEach { it.deleteRecursively() }
                check(batch.mkdirs())
                var remaining = 8 * 1024 * 1024
                val paths = files.mapIndexed { index, uri ->
                    require(uri.scheme == "content")
                    val name = contentResolver.query(
                        uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                        ?: error("Arquivo sem nome")
                    val safeName = name.replace(Regex("[^a-zA-Z0-9 ._-]"), "_")
                    val extension = safeName.substringAfterLast('.', "").lowercase()
                    require(extension.matches(Regex("[a-z0-9]{1,12}")))
                    require(extensions.isEmpty() || extension in extensions)
                    val folder = File(batch, index.toString())
                    check(folder.mkdir())
                    val base = safeName.substringBeforeLast('.').take(96)
                    val target = File(folder, "$base.$extension")
                    contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                remaining -= count
                                require(remaining >= 0)
                                output.write(buffer, 0, count)
                            }
                        }
                    } ?: error("Arquivo indisponível")
                    target.absolutePath
                }
                runOnUiThread { result.success(paths) }
            } catch (_: Exception) {
                batch.deleteRecursively()
                runOnUiThread {
                    result.error("ATTACHMENT_IMPORT", "Selecione arquivos compatíveis, até 8 MiB ao todo.", null)
                }
            }
        }.start()
    }

    override fun onStop() {
        audioDiagnostic.stop()
        voiceNotes.stopAll()
        pagerAudio.stop()
        super.onStop()
    }

    override fun onDestroy() {
        pagerAudio.destroy()
        invitationQrResult?.success(null)
        invitationQrResult = null
        attachmentResult?.error("ATTACHMENT_INTERRUPTED", "Seleção interrompida.", null)
        attachmentResult = null
        localMediaResult?.error("MEDIA_INTERRUPTED", "Seleção de mídia interrompida.", null)
        localMediaResult = null
        bleController?.stopMesh()
        rnodeController?.dispose()
        super.onDestroy()
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = ks.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }
        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")

        // Tenta StrongBox dedicado (API 28+); faz fallback seguro para TEE AndroidKeyStore
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val strongBoxSpec = KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setIsStrongBoxBacked(true)
                    .build()
                keyGen.init(strongBoxSpec)
                return keyGen.generateKey()
            } catch (_: StrongBoxUnavailableException) {
                // Dispositivo sem chip StrongBox separado -> prossegue com TEE padrão
            } catch (_: Exception) {
                // Fallback seguro para TEE padrão
            }
        }

        val teeSpec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGen.init(teeSpec)
        return keyGen.generateKey()
    }

    @Suppress("DEPRECATION")
    private fun inspectKeystoreSecurityInfo(): Map<String, Any> {
        val key = getOrCreateKey()
        val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
        val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
        val levelStr: String
        val inSecureHw: Boolean
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> {
                    levelStr = "STRONGBOX"
                    inSecureHw = true
                }
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> {
                    levelStr = "TRUSTED_ENVIRONMENT"
                    inSecureHw = true
                }
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> {
                    levelStr = "SOFTWARE"
                    inSecureHw = false
                }
                else -> {
                    levelStr = "UNKNOWN_HARDWARE"
                    inSecureHw = info.isInsideSecureHardware
                }
            }
        } else {
            inSecureHw = info.isInsideSecureHardware
            levelStr = if (inSecureHw) "TRUSTED_ENVIRONMENT" else "SOFTWARE"
        }
        return mapOf(
            "securityLevel" to levelStr,
            "isInsideSecureHardware" to inSecureHw,
            "keyAlias" to keyAlias
        )
    }

    private fun storeEncryptedSecret(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ct = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val combined = ByteArray(1 + iv.size + ct.size)
        combined[0] = iv.size.toByte()
        System.arraycopy(iv, 0, combined, 1, iv.size)
        System.arraycopy(ct, 0, combined, 1 + iv.size, ct.size)
        val encoded = Base64.encodeToString(combined, Base64.NO_WRAP)
        getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(key, encoded)
            .apply()
    }

    private fun readEncryptedSecret(key: String): String? {
        val encoded = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(key, null) ?: return null
        val combined = Base64.decode(encoded, Base64.NO_WRAP)
        if (combined.size < 2) return null
        val ivLen = combined[0].toInt() and 0xFF
        if (combined.size <= 1 + ivLen) return null
        val iv = combined.copyOfRange(1, 1 + ivLen)
        val ct = combined.copyOfRange(1 + ivLen, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        val clear = cipher.doFinal(ct)
        return String(clear, StandardCharsets.UTF_8)
    }
}
