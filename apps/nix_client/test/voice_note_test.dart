import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/voice_note.dart';
import 'package:nix_client/features/chat/voice_note_dialog.dart';

void main() {
  test('WAV aceita somente PCM do formato e do tamanho acordados', () {
    final note = VoiceNote.fromPcm(Uint8List.fromList([1, 2, 3, 4]));
    final encoded = note.toWav();
    expect(VoiceNote.fromWav(encoded).pcm, [1, 2, 3, 4]);
    expect(() => VoiceNote.fromPcm(Uint8List(1)), throwsFormatException);
    expect(() => VoiceNote.fromPcm(Uint8List(VoiceNote.maximumPcmBytes + 2)),
        throwsFormatException);
    encoded[24] = 0;
    expect(() => VoiceNote.fromWav(encoded), throwsFormatException);
  });

  testWidgets('pausa e prévia precedem a confirmação explícita do envio',
      (tester) async {
    final methods = <String>[];
    final sent = <int>[];
    final channel =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    channel.setMockMethodCallHandler(VoiceNoteDialog.channel, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'status' => {'state': 'recording', 'samples': 8000, 'peak': 512},
        'finish' => Uint8List.fromList([1, 2, 3, 4]),
        'playing' => true,
        _ => null,
      };
    });
    addTearDown(
        () => channel.setMockMethodCallHandler(VoiceNoteDialog.channel, null));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => VoiceNoteDialog.record(
            onSend: (note) async => sent.addAll(note.pcm),
          ),
        ),
        child: const Text('Abrir'),
      );
    }))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(methods, isEmpty);
    await tester.tap(find.text('Gravar'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Pausar'));
    await tester.pumpAndSettle();
    expect(find.text('Gravação pausada'), findsOneWidget);
    await tester.tap(find.text('Retomar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pré-visualizar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproduzir'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.tap(find.text('Enviar voz'));
    await tester.pumpAndSettle();
    expect(sent, [1, 2, 3, 4]);
    expect(
        methods,
        containsAllInOrder(
            ['start', 'pause', 'resume', 'finish', 'play', 'cancel']));
  });

  testWidgets('ao reproduzir um áudio o diálogo pode ser fechado imediatamente',
      (tester) async {
    final methods = <String>[];
    final channel =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    channel.setMockMethodCallHandler(VoiceNoteDialog.channel, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'play' => null,
        'stopPlayback' => null,
        'cancel' => null,
        'playing' => true,
        _ => null,
      };
    });
    addTearDown(
        () => channel.setMockMethodCallHandler(VoiceNoteDialog.channel, null));

    final testNote = VoiceNote.fromPcm(Uint8List.fromList([10, 20, 30, 40]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => VoiceNoteDialog.listen(
                  load: () async => testNote,
                ),
              ),
              child: const Text('Ouvir Áudio'),
            );
          }),
        ),
      ),
    );

    // Abre o diálogo
    await tester.tap(find.text('Ouvir Áudio'));
    await tester.pumpAndSettle();

    expect(find.text('Mensagem de voz'), findsOneWidget);
    expect(find.text('Reproduzir'), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);

    // Inicia reprodução
    await tester.tap(find.text('Reproduzir'));
    await tester.pumpAndSettle();

    expect(methods, contains('play'));
    expect(find.text('Parar'), findsOneWidget);

    // O botão 'Fechar' permanece acessível e clicável mesmo durante reprodução
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    // Diálogo fecha com sucesso
    expect(find.text('Mensagem de voz'), findsNothing);
    expect(methods, contains('cancel'));
  });
}
