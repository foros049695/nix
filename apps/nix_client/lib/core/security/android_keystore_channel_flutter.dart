import 'package:flutter/services.dart';

const MethodChannel _nixKeystoreChannel =
    MethodChannel('com.projetonix.nix/keystore');

Future<T?> invokeKeystoreChannel<T>(
  String method, [
  Map<String, dynamic>? arguments,
]) {
  return _nixKeystoreChannel.invokeMethod<T>(method, arguments);
}
