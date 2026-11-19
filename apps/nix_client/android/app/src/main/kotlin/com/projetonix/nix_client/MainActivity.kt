package com.projetonix.nix_client

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
  private val channelName = "com.projetonix.nix/keystore"
  private val keyAlias = "nix_vault_kek_v1"
  private val prefsName = "nix_keystore_vault_prefs"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        .setMethodCallHandler { call, result ->
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
              else -> result.notImplemented()
            }
          } catch (e: Exception) {
            result.error("KEYSTORE_ERROR", e.message ?: "Erro AndroidKeyStore", null)
          }
        }
  }

  private fun getOrCreateKey(): SecretKey {
    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val existing = ks.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
    if (existing != null) {
      return existing.secretKey
    }
    val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    val spec = KeyGenParameterSpec.Builder(
      keyAlias,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
    )
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build()
    keyGen.init(spec)
    return keyGen.generateKey()
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
