package com.projetonix.nix_client

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Controlador nativo de Bluetooth Low Energy (BLE GATT Server + Client + Scanner + Advertiser)
 * para malha de proximidade física do Projeto Nix (protocolo binário NIXB).
 */
class NixBleMeshController(
    private val activity: Activity,
    private val channel: MethodChannel
) {
    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
        val PACKET_CHAR_UUID: UUID = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb")
        const val PERMISSION_REQUEST_CODE = 49101
        private val MAGIC_NIXB = byteArrayOf(0x4E, 0x49, 0x58, 0x42)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager: BluetoothManager? =
        activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter?
        get() = bluetoothManager?.adapter

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null

    private var isAdvertising = false
    private var isScanning = false
    private var isGattServerActive = false
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Buffer de remontagem por dispositivo remoto para pacotes NIXB fragmentados por MTU
    private val rxBuffers = ConcurrentHashMap<String, ByteArrayOutputStream>()

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBluetoothStatus" -> result.success(buildStatusMap())
            "requestPermissions" -> requestBlePermissions(result)
            "startMesh" -> {
                val localCardId = call.argument<String>("localCardId") ?: "NIX-LOCAL"
                result.success(startMesh(localCardId))
            }
            "stopMesh" -> {
                stopMesh()
                result.success(true)
            }
            "sendPacket" -> {
                val address = call.argument<String>("deviceAddress")
                val bytes = call.argument<ByteArray>("bytes")
                if (address.isNullOrEmpty() || bytes == null || bytes.isEmpty()) {
                    result.success(mapOf("delivered" to false, "error" to "Parâmetros BLE inválidos"))
                } else {
                    sendPacketToPeer(address, bytes, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN
            )
        }
    }

    fun hasBlePermissions(): Boolean {
        return requiredPermissions().all { perm ->
            ContextCompat.checkSelfPermission(activity, perm) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        if (hasBlePermissions()) {
            result.success(mapOf("granted" to true))
            return
        }
        pendingPermissionResult?.success(mapOf("granted" to false))
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, requiredPermissions(), PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(mapOf("granted" to granted))
        pendingPermissionResult = null
        return true
    }

    private fun buildStatusMap(): Map<String, Any> {
        val adapter = bluetoothAdapter
        val supported = adapter != null &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val enabled = try {
            adapter?.isEnabled == true
        } catch (_: SecurityException) {
            false
        }
        val perms = hasBlePermissions()
        val detail = when {
            !supported -> "Hardware Bluetooth LE não suportado neste dispositivo."
            !perms -> "Permissões Bluetooth LE ainda não concedidas."
            !enabled -> "Adaptador Bluetooth desligado — ative o Bluetooth do celular."
            isGattServerActive && isScanning -> "BLE Mesh operacional (GATT Server + Scan + Adv)."
            else -> "Adaptador BLE pronto para iniciar malha."
        }
        return mapOf(
            "supported" to supported,
            "enabled" to enabled,
            "permissionsGranted" to perms,
            "advertising" to isAdvertising,
            "scanning" to isScanning,
            "gattServerActive" to isGattServerActive,
            "detail" to detail
        )
    }

    @SuppressLint("MissingPermission")
    private fun startMesh(localCardId: String): Map<String, Any> {
        val adapter = bluetoothAdapter
        if (adapter == null || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return mapOf("started" to false, "detail" to "Bluetooth LE indisponível neste aparelho.")
        }
        if (!hasBlePermissions()) {
            return mapOf("started" to false, "detail" to "Conceda primeiro as permissões BLE.")
        }
        if (!adapter.isEnabled) {
            return mapOf("started" to false, "detail" to "Ligue o Bluetooth do aparelho para iniciar a malha.")
        }

        stopMesh()
        startGattServer()
        startAdvertising(localCardId)
        startScanning()

        val summary = "BLE Mesh iniciado (GATT=$isGattServerActive, Adv=$isAdvertising, Scan=$isScanning)."
        emitLog(summary)
        return mapOf("started" to (isGattServerActive || isScanning), "detail" to summary)
    }

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        val mgr = bluetoothManager ?: return
        val server = mgr.openGattServer(activity, gattServerCallback) ?: return
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val packetChar = BluetoothGattCharacteristic(
            PACKET_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE or
                BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(packetChar)
        val added = server.addService(service)
        gattServer = server
        isGattServerActive = added
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(localCardId: String) {
        val adv = bluetoothAdapter?.bluetoothLeAdvertiser
        if (adv == null) {
            isAdvertising = false
            emitLog("Aviso: chip Bluetooth não suporta modo BLE Peripheral/Advertiser (somente Scanner/Client).")
            return
        }
        advertiser = adv
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0)
            .build()

        // Pacote principal (<= 31B): apenas Service UUID de 128 bits
        val advData = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        // ScanResponse (<= 31B): prefixo do Card ID público (máx 13 bytes em um anúncio legado)
        val cardBytes = localCardId.toByteArray(StandardCharsets.UTF_8).take(13).toByteArray()
        val scanResp = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceData(ParcelUuid(SERVICE_UUID), cardBytes)
            .build()

        try {
            adv.startAdvertising(settings, advData, scanResp, advertiseCallback)
            isAdvertising = true
        } catch (e: Exception) {
            isAdvertising = false
            emitLog("Falha ao iniciar Advertising BLE: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        val sc = bluetoothAdapter?.bluetoothLeScanner ?: return
        scanner = sc
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            sc.startScan(listOf(filter), settings, scanCallback)
            isScanning = true
        } catch (e: Exception) {
            isScanning = false
            emitLog("Falha ao iniciar Scan BLE: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    fun stopMesh() {
        try {
            if (isScanning) {
                scanner?.stopScan(scanCallback)
            }
        } catch (_: Exception) {}
        try {
            if (isAdvertising) {
                advertiser?.stopAdvertising(advertiseCallback)
            }
        } catch (_: Exception) {}
        try {
            gattServer?.close()
        } catch (_: Exception) {}
        gattServer = null
        isScanning = false
        isAdvertising = false
        isGattServerActive = false
        rxBuffers.clear()
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isAdvertising = true
            emitLog("Anúncio BLE ativo (UUID 0000ff01-... · visível a celulares Nix próximos).")
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            emitLog("Advertising BLE falhou (código $errorCode).")
        }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val sr = result ?: return
            val device = sr.device ?: return
            val addr = device.address ?: return
            val serviceData = sr.scanRecord?.getServiceData(ParcelUuid(SERVICE_UUID))
            val peerCardId = if (serviceData != null && serviceData.isNotEmpty()) {
                String(serviceData, StandardCharsets.UTF_8).trim()
            } else {
                "NIX-${addr.takeLast(5)}"
            }
            val payload = mapOf(
                "address" to addr,
                "peerCardId" to peerCardId,
                "rssi" to sr.rssi
            )
            mainHandler.post {
                channel.invokeMethod("onPeerDiscovered", payload)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            emitLog("Scan BLE interrompido pelo SO (código $errorCode).")
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
            if (characteristic.uuid != PACKET_CHAR_UUID || value == null || value.isEmpty()) return

            val addr = device.address ?: "ble_unknown"
            val stream = rxBuffers.computeIfAbsent(addr) { ByteArrayOutputStream() }
            synchronized(stream) {
                // Novo pacote começa com magic "NIXB" -> reinicia buffer se havia resíduo
                if (value.size >= 4 &&
                    value[0] == MAGIC_NIXB[0] &&
                    value[1] == MAGIC_NIXB[1] &&
                    value[2] == MAGIC_NIXB[2] &&
                    value[3] == MAGIC_NIXB[3]
                ) {
                    stream.reset()
                }
                stream.write(value)
                val current = stream.toByteArray()
                if (current.size >= 7 &&
                    current[0] == MAGIC_NIXB[0] &&
                    current[1] == MAGIC_NIXB[1] &&
                    current[2] == MAGIC_NIXB[2] &&
                    current[3] == MAGIC_NIXB[3]
                ) {
                    val expectedPayloadLen = ((current[5].toInt() and 0xFF) shl 8) or
                        (current[6].toInt() and 0xFF)
                    val totalLen = 7 + expectedPayloadLen
                    if (current.size >= totalLen) {
                        val packetBytes = current.copyOfRange(0, totalLen)
                        stream.reset()
                        mainHandler.post {
                            channel.invokeMethod(
                                "onPacketReceived",
                                mapOf("address" to addr, "bytes" to packetBytes)
                            )
                        }
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun sendPacketToPeer(
        deviceAddress: String,
        bytes: ByteArray,
        result: MethodChannel.Result
    ) {
        val adapter = bluetoothAdapter
        if (adapter == null || !hasBlePermissions()) {
            result.success(mapOf("delivered" to false, "error" to "BLE não autorizado ou indisponível"))
            return
        }

        val device = try {
            adapter.getRemoteDevice(deviceAddress)
        } catch (e: Exception) {
            result.success(mapOf("delivered" to false, "error" to "Endereço BLE inválido: ${e.message}"))
            return
        }

        var completed = false
        var activeMtu = 23
        var chunkOffset = 0
        var targetChar: BluetoothGattCharacteristic? = null

        fun finish(gatt: BluetoothGatt?, delivered: Boolean, error: String? = null) {
            if (completed) return
            completed = true
            try {
                gatt?.disconnect()
                gatt?.close()
            } catch (_: Exception) {}
            mainHandler.post {
                val resp = mutableMapOf<String, Any>("delivered" to delivered, "mtu" to activeMtu)
                if (error != null) resp["error"] = error
                result.success(resp)
            }
        }

        fun writeNextChunk(gatt: BluetoothGatt) {
            val ch = targetChar ?: run {
                finish(gatt, false, "Característica NIXB indisponível")
                return
            }
            if (chunkOffset >= bytes.size) {
                finish(gatt, true)
                return
            }
            val maxChunk = (activeMtu - 3).coerceAtLeast(20)
            val end = (chunkOffset + maxChunk).coerceAtMost(bytes.size)
            val slice = bytes.copyOfRange(chunkOffset, end)
            chunkOffset = end

            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(
                    ch,
                    slice,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                ) == BluetoothStatusCodes.SUCCESS
            } else {
                ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                ch.value = slice
                gatt.writeCharacteristic(ch)
            }
            if (!ok) {
                finish(gatt, false, "Falha ao gravar fragmento BLE GATT")
            }
        }

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finish(gatt, false, "Erro de conexão GATT (status=$status)")
                    return
                }
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (!gatt.requestMtu(512)) {
                        gatt.discoverServices()
                    }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED && !completed) {
                    finish(gatt, false, "Desconectado antes do término da entrega")
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS && mtu >= 23) {
                    activeMtu = mtu
                }
                gatt.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finish(gatt, false, "Falha ao descobrir serviços GATT (status=$status)")
                    return
                }
                val svc = gatt.getService(SERVICE_UUID)
                val ch = svc?.getCharacteristic(PACKET_CHAR_UUID)
                if (ch == null) {
                    finish(gatt, false, "Serviço Nix BLE (0000ff01) não encontrado no par")
                    return
                }
                targetChar = ch
                writeNextChunk(gatt)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finish(gatt, false, "Erro de escrita GATT (status=$status)")
                    return
                }
                writeNextChunk(gatt)
            }
        }

        val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(activity, false, callback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(activity, false, callback)
        }

        mainHandler.postDelayed({
            if (!completed) {
                finish(gatt, false, "Tempo limite (12s) excedido na entrega BLE GATT")
            }
        }, 12_000L)
    }

    private fun emitLog(msg: String) {
        mainHandler.post {
            channel.invokeMethod("onMeshLog", msg)
        }
    }
}
