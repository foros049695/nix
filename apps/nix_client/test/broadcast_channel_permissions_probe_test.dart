import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/core/models/space.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

Future<Uint8List> _sealEnvelopePayload(
  SecretKeyData sessionKey,
  Map<String, Object?> payload,
) async {
  final clear = utf8.encode(jsonEncode(payload));
  final sealed = await SealedEnvelope.seal(key: sessionKey, plaintext: clear);
  return sealed.encode();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Canais de Transmissão — Permissões de Encaminhamento e Entrada (Probe)', () {
    test('forwardMessage bloqueia não-administrador em canal de transmissão e permite admin', () {
      final state = NixState(loadMockData: false);
      const externalAdmin = 'OTHER-ADMIN-9999-AAAA';
      final externalChannel = Channel(
        id: 'ch_announcement_external',
        spaceId: 'space_ext',
        name: 'noticias',
        topic: 'Canal externo',
        type: ChannelType.announcement,
        category: 'TRANSMISSÃO',
        ownerFingerprint: externalAdmin,
        admins: const [externalAdmin],
      );
      state.addSpace(
        Space(
          id: 'space_ext',
          name: 'Ext',
          initials: 'EE',
          description: 'd',
          ownerFingerprint: externalAdmin,
          channels: [externalChannel],
        ),
      );
      state.selectChannel(externalChannel);

      expect(state.sendMessage('direto'), isFalse);

      final sampleMsg = Message(
        id: 'm1',
        channelId: 'dm_saved_messages',
        senderName: 'eu',
        senderFingerprint: state.securityContext.myFingerprint,
        isMe: true,
        text: 'tentativa via encaminhamento',
        timestamp: DateTime.now(),
      );

      final blockedFwd = state.forwardMessage(
        sampleMsg,
        targetId: externalChannel.id,
        isChannel: true,
      );
      expect(
        blockedFwd,
        isFalse,
        reason: 'não-administrador não pode publicar via forwardMessage em canal de transmissão',
      );
      expect(state.currentMessages, isEmpty);

      // Canal próprio onde o usuário local é proprietário/admin deve aceitar encaminhamento
      state.createSpace(
        name: 'Meus Avisos',
        description: 'Transmissão própria',
        emoji: 'i:megaphone',
        isAnnouncementChannel: true,
      );
      final ownAnnouncement = state.currentChannel;
      expect(ownAnnouncement.type, equals(ChannelType.announcement));

      final allowedFwd = state.forwardMessage(
        sampleMsg,
        targetId: ownAnnouncement.id,
        isChannel: true,
      );
      expect(allowedFwd, isTrue);
      expect(state.currentMessages.map((m) => m.text), contains('tentativa via encaminhamento'));
    });

    test('forwardMessage respeita allowMessages, allowFiles e silenciamento no canal de destino', () {
      final state = NixState(loadMockData: false);
      final myFp = state.securityContext.myFingerprint;

      final readOnlyChannel = Channel(
        id: 'ch_readonly',
        spaceId: 'space_perm',
        name: 'somente-leitura',
        topic: 't',
        type: ChannelType.text,
        category: 'COMUNIDADE',
        permissions: const ChannelPermissions(allowMessages: false),
      );
      final noFilesChannel = Channel(
        id: 'ch_nofiles',
        spaceId: 'space_perm',
        name: 'sem-arquivos',
        topic: 't',
        type: ChannelType.text,
        category: 'COMUNIDADE',
        permissions: const ChannelPermissions(allowFiles: false),
      );
      final mutedChannel = Channel(
        id: 'ch_muted_me',
        spaceId: 'space_perm',
        name: 'silenciado',
        topic: 't',
        type: ChannelType.text,
        category: 'COMUNIDADE',
        mutedMembers: [myFp],
      );
      state.addSpace(
        Space(
          id: 'space_perm',
          name: 'Perm',
          initials: 'PM',
          description: 'd',
          channels: [readOnlyChannel, noFilesChannel, mutedChannel],
        ),
      );

      final textMsg = Message(
        id: 'm_txt',
        channelId: 'dm_saved_messages',
        senderName: 'eu',
        senderFingerprint: myFp,
        isMe: true,
        text: 'olá',
        timestamp: DateTime.now(),
      );
      final fileMsg = Message(
        id: 'm_file',
        channelId: 'dm_saved_messages',
        senderName: 'eu',
        senderFingerprint: myFp,
        isMe: true,
        text: 'arquivo',
        attachments: const ['/tmp/doc.pdf'],
        timestamp: DateTime.now(),
      );

      expect(state.forwardMessage(textMsg, targetId: readOnlyChannel.id, isChannel: true), isFalse);
      expect(state.forwardMessage(fileMsg, targetId: noFilesChannel.id, isChannel: true), isFalse);
      expect(state.forwardMessage(textMsg, targetId: noFilesChannel.id, isChannel: true), isTrue);
      expect(state.forwardMessage(textMsg, targetId: mutedChannel.id, isChannel: true), isFalse);
      expect(state.forwardMessage(textMsg, targetId: 'canal_inexistente', isChannel: true), isFalse);
    });

    test('processInboundEnvelope alcança checagem de admin em canais de transmissão e continua bloqueando canais comuns', () async {
      final state = NixState(loadMockData: false);
      const adminFp = 'NIX-ADMIN-7777-BBBB';
      const coAdminFp = 'NIX-COADMIN-8888-CCCC';

      final announcementChannel = Channel(
        id: 'ch_inbound_broadcast',
        spaceId: 'space_in',
        name: 'boletim',
        topic: 'Boletim oficial',
        type: ChannelType.announcement,
        category: 'TRANSMISSÃO',
        ownerFingerprint: adminFp,
        admins: const [adminFp, coAdminFp],
      );
      final regularTextChannel = Channel(
        id: 'ch_inbound_text',
        spaceId: 'space_in',
        name: 'bate-papo',
        topic: 'Sala comum',
        type: ChannelType.text,
        category: 'COMUNIDADE',
        ownerFingerprint: adminFp,
      );
      state.addSpace(
        Space(
          id: 'space_in',
          name: 'Inbound',
          initials: 'IN',
          description: 'd',
          ownerFingerprint: adminFp,
          channels: [announcementChannel, regularTextChannel],
        ),
      );

      final sessionKey = SecretKeyData.random(length: 32);

      // 1. Remetente não-admin em canal de transmissão -> rejeitado
      final nonAdminEnvelope = await _sealEnvelopePayload(sessionKey, {
        'id': 'm_non_admin',
        'sender': 'NIX-INTRUDER-0001',
        'text': 'Tentativa sem permissão',
      });
      final nonAdminAccepted = await state.processInboundEnvelope(
        mailboxId: announcementChannel.id,
        deliveryId: 'del_non_admin_1',
        ciphertext: nonAdminEnvelope,
        sessionKey: sessionKey,
      );
      expect(nonAdminAccepted, isFalse);

      // 2. Remetente ausente/vazio em canal de transmissão -> rejeitado
      final anonymousEnvelope = await _sealEnvelopePayload(sessionKey, {
        'id': 'm_anon',
        'text': 'Sem campo sender',
      });
      final anonAccepted = await state.processInboundEnvelope(
        mailboxId: announcementChannel.id,
        deliveryId: 'del_anon_1',
        ciphertext: anonymousEnvelope,
        sessionKey: sessionKey,
      );
      expect(anonAccepted, isFalse);

      // 3. Remetente admin em canal de transmissão -> aceito!
      final adminEnvelope = await _sealEnvelopePayload(sessionKey, {
        'id': 'm_admin',
        'sender': coAdminFp,
        'text': 'Comunicado oficial assinado pelo canal.',
      });
      final adminAccepted = await state.processInboundEnvelope(
        mailboxId: announcementChannel.id,
        deliveryId: 'del_admin_1',
        ciphertext: adminEnvelope,
        sessionKey: sessionKey,
      );
      expect(
        adminAccepted,
        isTrue,
        reason: 'envelope de administrador deve alcançar e passar pela checagem de canal de transmissão',
      );
      state.selectChannel(announcementChannel);
      expect(
        state.currentMessages.map((m) => m.text),
        equals(['Comunicado oficial assinado pelo canal.']),
      );

      // 4. Canal comum (não-transmissão) continua bloqueado no transporte genérico de mailbox
      final regularChannelEnvelope = await _sealEnvelopePayload(sessionKey, {
        'id': 'm_text_ch',
        'sender': adminFp,
        'text': 'Não deve entrar por processInboundEnvelope genérico',
      });
      final regularAccepted = await state.processInboundEnvelope(
        mailboxId: regularTextChannel.id,
        deliveryId: 'del_reg_1',
        ciphertext: regularChannelEnvelope,
        sessionKey: sessionKey,
      );
      expect(regularAccepted, isFalse);
    });
  });
}
