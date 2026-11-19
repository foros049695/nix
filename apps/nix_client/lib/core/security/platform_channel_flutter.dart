import 'package:flutter/services.dart';

const MethodChannel _platformChannel =
    MethodChannel('com.projetonix.nix/platform');
const MethodChannel _keystoreChannel =
    MethodChannel('com.projetonix.nix/keystore');

Future<Map<String, dynamic>?> invokePlatformRuntimeInfo() async {
  return _platformChannel.invokeMapMethod<String, dynamic>('getRuntimeInfo');
}

Future<Map<String, dynamic>?> invokeKeystoreSecurityInfo() async {
  return _keystoreChannel.invokeMapMethod<String, dynamic>('getKeystoreInfo');
}
