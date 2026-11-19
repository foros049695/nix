import 'dart:ffi';

DynamicLibrary openAndroidSqlCipherLibrary() =>
    DynamicLibrary.open('libsqlcipher.so');
