import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/calls/onion_voice_link.dart';

void main() {
  test('dois clientes trocam PCM e chat autenticados por uma sala Onion',
      () async {
    final directory = await Directory.systemTemp.createTemp('nix-voice-link');
    addTearDown(() => directory.delete(recursive: true));
    final cookie = File('${directory.path}/control');
    await cookie.writeAsBytes(List.filled(32, 5));
    final host = 'a' * 56;
    final target = Completer<int>();
    final control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(control.close);
    control.listen((socket) {
      utf8.decoder.bind(socket).transform(const LineSplitter()).listen((line) {
        if (line.startsWith('AUTHENTICATE ')) {
          socket.write('250 OK\r\n');
        } else if (line
            .startsWith('ADD_ONION NEW:ED25519-V3 Flags=DiscardPK ')) {
          target.complete(int.parse(line.split(':').last));
          socket.write('250-ServiceID=$host\r\n250 OK\r\n');
        } else {
          socket.write('510 Invalid command\r\n');
        }
      });
    });

    final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(socks.close);
    socks.listen((socket) {
      unawaited(_proxy(socket, '$host.onion', target.future));
    });
    final tor = (
      socksPort: socks.port,
      controlPort: control.port,
      cookiePath: cookie.path
    );
    var available = true;
    final caller = await OnionVoiceLink.host(tor, () => available);
    addTearDown(caller.close);
    final invite = caller.invite!;
    final receiver = OnionVoiceLink.join(invite, tor, () => available);
    addTearDown(receiver.close);
    final third = OnionVoiceLink.join(invite, tor, () => available);
    addTearDown(third.close);

    final callerEvent = caller.updates.first;
    final receiverEvent = receiver.updates.first;
    caller.setAudio(Uint8List.fromList([0, 5, 12, 120]));
    receiver.setAudio(Uint8List.fromList([12, 8, 4, 16]));
    caller.sendText('Mensagem do anfitrião');
    receiver.sendText('Mensagem do convidado');
    await receiver.tick();
    final a = await callerEvent;
    final b = await receiverEvent;
    expect(a.audio, [12, 8, 4, 16]);
    expect(a.text, 'Mensagem do convidado');
    expect(b.audio, [0, 5, 12, 120]);
    expect(b.text, 'Mensagem do anfitrião');
    expect(caller.peerConnected, isTrue);
    expect(receiver.peerConnected, isTrue);
    expect(caller.invite, isNull);
    await expectLater(third.tick(), throwsStateError);

    await receiver.tick(); // acknowledges delivery of the host message
    final repeated = receiver.updates.first;
    caller.sendText('Mensagem do anfitrião');
    await receiver.tick();
    expect((await repeated).text, 'Mensagem do anfitrião');

    available = false;
    expect(receiver.available, isFalse);
    expect(() => receiver.sendText('bloqueada'), throwsStateError);
  }, timeout: const Timeout(Duration(seconds: 15)));
}

Future<void> _proxy(
    Socket socket, String expectedHost, Future<int> target) async {
  Socket? upstream;
  final pending = BytesBuilder();
  var stage = 0;
  var requiredBytes = 3;
  var busy = false;
  late StreamSubscription<Uint8List> subscription;
  Future<void> advance() async {
    if (busy || pending.length < requiredBytes) return;
    busy = true;
    try {
      while (pending.length >= requiredBytes && upstream == null) {
        final bytes = pending.takeBytes();
        final packet = bytes.sublist(0, requiredBytes);
        pending.add(bytes.sublist(requiredBytes));
        switch (stage++) {
          case 0:
            expect(packet, [5, 1, 2]);
            socket.add([5, 2]);
            requiredBytes = 47;
          case 1:
            expect(packet.take(2), [1, 22]);
            expect(packet[24], 22);
            expect(packet.sublist(2, 24), packet.sublist(25));
            socket.add([1, 0]);
            requiredBytes = 5;
          case 2:
            expect(packet.take(4), [5, 1, 0, 3]);
            requiredBytes = packet.last + 2;
          default:
            expect(ascii.decode(packet.sublist(0, packet.length - 2)),
                expectedHost);
            expect(packet.sublist(packet.length - 2), [0, 80]);
            final peer = await Socket.connect(
                InternetAddress.loopbackIPv4, await target);
            upstream = peer;
            peer.listen(socket.add, onDone: () => socket.close());
            socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
            if (pending.isNotEmpty) peer.add(pending.takeBytes());
        }
      }
    } catch (_) {
      socket.destroy();
      upstream?.destroy();
      await subscription.cancel();
      rethrow;
    } finally {
      busy = false;
    }
  }

  final done = Completer<void>();
  subscription = socket.listen((bytes) {
    final peer = upstream;
    if (peer != null) {
      peer.add(bytes);
    } else {
      pending.add(bytes);
      unawaited(advance());
    }
  }, onDone: () {
    upstream?.destroy();
    socket.destroy();
    done.complete();
  }, onError: done.completeError);
  try {
    await done.future;
  } finally {
    await subscription.cancel();
  }
}
