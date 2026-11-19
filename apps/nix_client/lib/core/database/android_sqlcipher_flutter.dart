import 'dart:ffi';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

DynamicLibrary openAndroidSqlCipherLibrary() => openCipherOnAndroid();
