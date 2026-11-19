package com.projetonix.nix_client

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
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

    private var bleController: NixBleMeshController? = null
    private var rnodeController: NixRNodeRadioController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

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
        if (bleController?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
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
