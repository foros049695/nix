import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/anti_forensic_shredder.dart';

// Observa o arquivo real, inclusive logo após open(), antes da truncagem final.
class ObservedFile implements File {
  final File file;
  final List<int> sizes = [];
  List<int>? finalBytes;
  ObservedFile(this.file);

  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  Directory get parent => file.parent;
  @override
  Future<File> rename(String path) => file.rename(path);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final handle = await file.open(mode: mode);
    sizes.add(await file.length());
    return ObservedHandle(handle, this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ObservedHandle implements RandomAccessFile {
  final RandomAccessFile handle;
  final ObservedFile observed;
  ObservedHandle(this.handle, this.observed);

  @override
  Future<RandomAccessFile> setPosition(int position) =>
      handle.setPosition(position);
  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    final result = await handle.writeFrom(buffer, start, end);
    observed.sizes.add(await observed.file.length());
    return result;
  }

  @override
  Future<RandomAccessFile> flush() => handle.flush();
  @override
  Future<RandomAccessFile> truncate(int length) async {
    observed.finalBytes = await observed.file.readAsBytes();
    return handle.truncate(length);
  }

  @override
  Future<void> close() => handle.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('nix_wipe_probe_'));
  tearDown(() async => root.delete(recursive: true));

  test('customBaseDir preserva sentinelas em um HOME vizinho', () async {
    final home = Directory('${root.path}/home');
    final base = await Directory('${root.path}/custom').create();
    final defaults = await Directory('${home.path}/.local/share/nix')
        .create(recursive: true);
    final names = [
      'vault_bootstrap.json',
      'nix_local_v4.db',
      'client_prefs_v4.json'
    ];
    for (final name in names) {
      await File('${defaults.path}/$name').writeAsString('sentinela');
      await File('${base.path}/$name').writeAsString('descartavel');
    }
    final result = await Process.run('dart', [
      '--packages=.dart_tool/package_config.json',
      'test/helpers/panic_wipe.dart',
      base.path,
    ], environment: {
      'HOME': home.path
    });
    expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
    for (final name in names) {
      expect(await File('${defaults.path}/$name').exists(), isTrue,
          reason: name);
      expect(await File('${defaults.path}/$name').readAsString(), 'sentinela');
      expect(await File('${base.path}/$name').exists(), isFalse);
    }
  });

  test('sobrescreve in-place sem truncar nem acrescentar durante as passagens',
      () async {
    final original =
        List<int>.filled(AntiForensicShredder.chunkSize + 17, 0xA5);
    final file = File('${root.path}/secret');
    await file.writeAsBytes(original);
    final observed = ObservedFile(file);
    expect(await AntiForensicShredder.shredFile(observed), original.length * 3);
    expect(observed.sizes, isNotEmpty);
    expect(observed.sizes, everyElement(original.length));
    expect(observed.finalBytes, everyElement(0));
    expect(observed.finalBytes!.length, original.length);
    expect(await file.exists(), isFalse);
  });
  test('alvos explícitos ficam no diretório e bootstrap é destruído primeiro',
      () async {
    final targets = AntiForensicShredder.wipeTargets(
        home: '/outro/home', customBaseDir: root.path);
    expect(targets, everyElement(startsWith('${root.path}/')));
    expect(targets.first, '${root.path}/vault_bootstrap.json');
    for (final path in targets) {
      await File(path).writeAsString('segredo');
    }
    final report =
        await AntiForensicShredder.panicWipeAccount(customBaseDir: root.path);
    expect(report.shreddedPaths, targets);
    expect(report.memoryWiped, isFalse);
    expect(report.errors, isEmpty);
  });

  test('falha em um alvo é relatada sem impedir os demais arquivos', () async {
    final broken = '${root.path}/vault_bootstrap.json';
    await Directory(broken).create();
    final db = File('${root.path}/nix_local_v4.db');
    await db.writeAsString('banco');
    final storage = await Directory('${root.path}/storage').create();
    final sentinel = File('${root.path}/outside');
    await sentinel.writeAsString('sentinela');
    await Link('${storage.path}/link').create(sentinel.path);
    await File('${storage.path}/cache').writeAsString('cache');
    final report =
        await AntiForensicShredder.panicWipeAccount(customBaseDir: root.path);
    expect(report.errors, contains(broken));
    expect(report.errors, isNot(contains('${storage.path}/link')));
    expect(await storage.exists(), isFalse);
    expect(report.filesOverwritten, 2);
    expect(await db.exists(), isFalse);
    expect(await File('${storage.path}/cache').exists(), isFalse);
    expect(await sentinel.readAsString(), 'sentinela');
  });
}
