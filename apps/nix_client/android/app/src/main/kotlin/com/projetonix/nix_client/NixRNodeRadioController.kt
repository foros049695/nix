package com.projetonix.nix_client

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Controlador nativo de Rádio LoRa / Reticulum RNode (USB-OTG Serial + BLE Nordic UART Service)
 * com transporte binário de quadros KISS.
 */
class NixRNodeRadioController(
    private val activity: Activity,
    private val channel: MethodChannel
) {
    companion object {
        private const val ACTION_USB_PERMISSION = "com.projetonix.nix_client.USB_RNODE_PERMISSION"
        private val NUS_SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        private val NUS_TX_CHAR_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        private val NUS_RX_CHAR_UUID: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // VIDs comuns em placas LoRa / RNode / Meshtastic (CP210x, CH340, FTDI, ESP32-S3, Heltec, RAK)
        private val KNOWN_LORA_VIDS = setOf(0x10C4, 0x1A86, 0x0403, 0x303A, 0x239A, 0x1915, 0x2886)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val usbManager: UsbManager? =
        activity.getSystemService(Context.USB_SERVICE) as? UsbManager

    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var usbEndpointIn: UsbEndpoint? = null
    private var usbEndpointOut: UsbEndpoint? = null
    private var usbReaderThread: Thread? = null
    private val usbReading = AtomicBoolean(false)

    private var bleGatt: BluetoothGatt? = null
    private var bleTxChar: BluetoothGattCharacteristic? = null
    private var activeTransport: String? = null

    private var pendingUsbResult: MethodChannel.Result? = null
    private var pendingDetectProbe: ByteArray? = null

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_USB_PERMISSION) return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            @Suppress("DEPRECATION")
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            val res = pendingUsbResult
            val probe = pendingDetectProbe
            pendingUsbResult = null
            pendingDetectProbe = null
            if (res == null) return
            if (granted && device != null) {
                res.success(openUsbSerialDevice(device, probe))
            } else {
                res.success(mapOf("connected" to false, "detail" to "Permissão USB-OTG negada pelo usuário."))
            }
        }
    }

    private var receiverRegistered = false

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDevices" -> result.success(listAvailableDevices())
            "connectDevice" -> {
                val id = call.argument<String>("id") ?: ""
                val transport = call.argument<String>("transport") ?: "usb_otg"
                val detectProbe = call.argument<ByteArray>("detectProbe")
                if (transport == "usb_otg") {
                    connectUsbDevice(id, detectProbe, result)
                } else {
                    connectBleRNode(id, detectProbe, result)
                }
            }
            "sendKissFrame" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.success(mapOf("sent" to false, "detail" to "Quadro KISS vazio."))
                } else {
                    result.success(sendKissBytes(bytes))
                }
            }
            "disconnect" -> {
                disconnect()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun listAvailableDevices(): List<Map<String, Any>> {
        val devices = mutableListOf<Map<String, Any>>()

        // 1. Dispositivos USB-OTG conectados
        val usbMap = usbManager?.deviceList ?: emptyMap()
        for ((name, dev) in usbMap) {
            val vidHex = dev.vendorId.toString(16).padStart(4, '0')
            val pidHex = dev.productId.toString(16).padStart(4, '0')
            val label = dev.productName ?: "USB Serial ($vidHex:$pidHex)"
            val knownHint = if (KNOWN_LORA_VIDS.contains(dev.vendorId)) "Chipset LoRa/RNode reconhecido" else "USB-OTG Serial"
            devices.add(
                mapOf(
                    "id" to name,
                    "name" to label,
                    "transport" to "usb_otg",
                    "detail" to "VID:$vidHex PID:$pidHex · $knownHint"
                )
            )
        }

        // 2. Dispositivos Bluetooth pareados compatíveis com RNode/Meshtastic BLE UART
        try {
            val btMgr = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val bonded = btMgr?.adapter?.bondedDevices ?: emptySet()
            for (dev in bonded) {
                val devName = dev.name ?: continue
                if (devName.contains("RNode", ignoreCase = true) ||
                    devName.contains("LoRa", ignoreCase = true) ||
                    devName.contains("Meshtastic", ignoreCase = true) ||
                    devName.contains("T-Beam", ignoreCase = true) ||
                    devName.contains("Heltec", ignoreCase = true) ||
                    devName.contains("RAK", ignoreCase = true)
                ) {
                    devices.add(
                        mapOf(
                            "id" to dev.address,
                            "name" to devName,
                            "transport" to "ble_uart",
                            "detail" to "BLE Nordic UART (${dev.address})"
                        )
                    )
                }
            }
        } catch (_: SecurityException) {}

        return devices
    }

    private fun ensureUsbReceiverRegistered() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(usbPermissionReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun connectUsbDevice(
        deviceName: String,
        detectProbe: ByteArray?,
        result: MethodChannel.Result
    ) {
        val mgr = usbManager
        val device = mgr?.deviceList?.get(deviceName)
        if (mgr == null || device == null) {
            result.success(mapOf("connected" to false, "detail" to "Dispositivo USB-OTG não encontrado."))
            return
        }
        if (!mgr.hasPermission(device)) {
            ensureUsbReceiverRegistered()
            pendingUsbResult = result
            pendingDetectProbe = detectProbe
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val pi = PendingIntent.getBroadcast(activity, 0, Intent(ACTION_USB_PERMISSION), flags)
            mgr.requestPermission(device, pi)
            return
        }
        result.success(openUsbSerialDevice(device, detectProbe))
    }

    private fun openUsbSerialDevice(device: UsbDevice, detectProbe: ByteArray?): Map<String, Any> {
        disconnect()
        val mgr = usbManager ?: return mapOf("connected" to false, "detail" to "UsbManager indisponível.")
        val conn = mgr.openDevice(device)
            ?: return mapOf("connected" to false, "detail" to "Não foi possível abrir o dispositivo USB.")

        var foundIface: UsbInterface? = null
        var epIn: UsbEndpoint? = null
        var epOut: UsbEndpoint? = null

        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            var candidateIn: UsbEndpoint? = null
            var candidateOut: UsbEndpoint? = null
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_IN) candidateIn = ep
                    if (ep.direction == UsbConstants.USB_DIR_OUT) candidateOut = ep
                }
            }
            if (candidateIn != null && candidateOut != null) {
                foundIface = iface
                epIn = candidateIn
                epOut = candidateOut
                break
            }
        }

        if (foundIface == null || epIn == null || epOut == null) {
            conn.close()
            return mapOf("connected" to false, "detail" to "Interface serial bulk IN/OUT não encontrada no USB.")
        }

        if (!conn.claimInterface(foundIface, true)) {
            conn.close()
            return mapOf("connected" to false, "detail" to "Falha ao reivindicar interface serial USB-OTG.")
        }

        // Configura 115200 8N1 (CDC-ACM SET_LINE_CODING e CP210x IFC_ENABLE)
        val lineCoding = byteArrayOf(0x00, 0xC2.toByte(), 0x01, 0x00, 0x00, 0x00, 0x08)
        conn.controlTransfer(0x21, 0x20, 0, foundIface.id, lineCoding, lineCoding.size, 500)
        conn.controlTransfer(0x21, 0x22, 0x03, foundIface.id, null, 0, 500)
        if (device.vendorId == 0x10C4) {
            conn.controlTransfer(0x41, 0x00, 0x0001, 0, null, 0, 500) // CP210x enable UART
        }

        usbConnection = conn
        usbInterface = foundIface
        usbEndpointIn = epIn
        usbEndpointOut = epOut
        activeTransport = "usb_otg"
        usbReading.set(true)

        usbReaderThread = Thread {
            val buf = ByteArray(512)
            while (usbReading.get()) {
                val len = conn.bulkTransfer(epIn, buf, buf.size, 300)
                if (len > 0) {
                    val data = buf.copyOfRange(0, len)
                    mainHandler.post {
                        channel.invokeMethod(
                            "onKissBytesReceived",
                            mapOf("source" to (device.productName ?: "usb_rnode"), "bytes" to data)
                        )
                    }
                }
            }
        }.apply {
            isDaemon = true
            start()
        }

        if (detectProbe != null && detectProbe.isNotEmpty()) {
            conn.bulkTransfer(epOut, detectProbe, detectProbe.size, 1000)
        }

        return mapOf(
            "connected" to true,
            "detail" to "RNode USB-OTG conectado (${device.productName ?: device.deviceName} · 115200 8N1 · KISS ativo)."
        )
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun connectBleRNode(
        address: String,
        detectProbe: ByteArray?,
        result: MethodChannel.Result
    ) {
        disconnect()
        val btMgr = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = btMgr?.adapter
        if (adapter == null) {
            result.success(mapOf("connected" to false, "detail" to "Adaptador Bluetooth indisponível."))
            return
        }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: Exception) {
            result.success(mapOf("connected" to false, "detail" to "Endereço BLE RNode inválido."))
            return
        }

        var replied = false
        fun reply(ok: Boolean, detail: String) {
            if (replied) return
            replied = true
            mainHandler.post { result.success(mapOf("connected" to ok, "detail" to detail)) }
        }

        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                    if (!replied) reply(false, "Falha de conexão BLE NUS com RNode (status=$status).")
                    return
                }
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt.requestMtu(247)
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                gatt.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val nus = gatt.getService(NUS_SERVICE_UUID)
                val tx = nus?.getCharacteristic(NUS_TX_CHAR_UUID)
                val rx = nus?.getCharacteristic(NUS_RX_CHAR_UUID)
                if (tx == null || rx == null) {
                    reply(false, "Serviço Nordic UART (6E400001) não encontrado no RNode BLE.")
                    return
                }
                bleGatt = gatt
                bleTxChar = tx
                activeTransport = "ble_uart"
                gatt.setCharacteristicNotification(rx, true)
                val cccd = rx.getDescriptor(CCCD_UUID)
                if (cccd != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    } else {
                        cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        gatt.writeDescriptor(cccd)
                    }
                }
                if (detectProbe != null && detectProbe.isNotEmpty()) {
                    sendKissBytes(detectProbe)
                }
                reply(true, "RNode BLE Nordic UART conectado ($address).")
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray
            ) {
                if (characteristic.uuid == NUS_RX_CHAR_UUID && value.isNotEmpty()) {
                    mainHandler.post {
                        channel.invokeMethod(
                            "onKissBytesReceived",
                            mapOf("source" to address, "bytes" to value)
                        )
                    }
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                val value = characteristic.value ?: return
                if (characteristic.uuid == NUS_RX_CHAR_UUID && value.isNotEmpty()) {
                    mainHandler.post {
                        channel.invokeMethod(
                            "onKissBytesReceived",
                            mapOf("source" to address, "bytes" to value)
                        )
                    }
                }
            }
        }

        bleGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(activity, false, cb, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(activity, false, cb)
        }

        mainHandler.postDelayed({
            if (!replied) reply(false, "Timeout ao conectar ao RNode BLE ($address).")
        }, 10_000L)
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun sendKissBytes(bytes: ByteArray): Map<String, Any> {
        return when (activeTransport) {
            "usb_otg" -> {
                val conn = usbConnection
                val outEp = usbEndpointOut
                if (conn == null || outEp == null) {
                    mapOf("sent" to false, "detail" to "Conexão USB-OTG fechada.")
                } else {
                    val written = conn.bulkTransfer(outEp, bytes, bytes.size, 1500)
                    if (written >= bytes.size) {
                        mapOf("sent" to true, "detail" to "KISS TX USB-OTG: $written bytes enviados.")
                    } else {
                        mapOf("sent" to false, "detail" to "Erro bulkTransfer USB-OTG (written=$written).")
                    }
                }
            }
            "ble_uart" -> {
                val gatt = bleGatt
                val tx = bleTxChar
                if (gatt == null || tx == null) {
                    mapOf("sent" to false, "detail" to "Conexão BLE NUS fechada.")
                } else {
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gatt.writeCharacteristic(
                            tx,
                            bytes,
                            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                        ) == BluetoothStatusCodes.SUCCESS
                    } else {
                        tx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                        tx.value = bytes
                        gatt.writeCharacteristic(tx)
                    }
                    mapOf("sent" to ok, "detail" to if (ok) "KISS TX BLE NUS: ${bytes.size} bytes enviados." else "Falha TX BLE NUS.")
                }
            }
            else -> mapOf("sent" to false, "detail" to "Nenhum transceptor LoRa/RNode conectado.")
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        usbReading.set(false)
        try {
            usbReaderThread?.interrupt()
        } catch (_: Exception) {}
        usbReaderThread = null
        try {
            usbInterface?.let { usbConnection?.releaseInterface(it) }
            usbConnection?.close()
        } catch (_: Exception) {}
        usbInterface = null
        usbConnection = null
        usbEndpointIn = null
        usbEndpointOut = null
        try {
            bleGatt?.disconnect()
            bleGatt?.close()
        } catch (_: Exception) {}
        bleGatt = null
        bleTxChar = null
        activeTransport = null
    }

    fun dispose() {
        disconnect()
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(usbPermissionReceiver)
            } catch (_: Exception) {}
            receiverRegistered = false
        }
    }
}
