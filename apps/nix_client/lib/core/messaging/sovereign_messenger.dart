import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';
import '../database/local_database.dart';
import '../database/repositories.dart';
import '../security/local_image_helper.dart';

/// Resultado da importação out-of-band (QR/JSON) de um Card ID soberano.
enum CardImportStatus {
  importedVerified,
  importedUnverified,
  keyChangedWarning,
  invalidSignatureOrExpired,
}

class CardImportResult {
  final CardImportStatus status;
  final String? publicId;
  final String? displayName;
  final String? mailboxId;
  final SignedPreKeyBundle? signedPreKeyBundle;
  final String? reason;

  const CardImportResult({
    required this.status,
    this.publicId,
    this.displayName,
    this.mailboxId,
    this.signedPreKeyBundle,
    this.reason,
  });
}

/// Manifesto criptográfico de anexo fragmentado E2EE enviado dentro do envelope Ratchet.
class AttachmentManifest {
  final String objectId;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final String plaintextSha256Hex;
  final String objectKeyBase64;
  final List<String> chunkCiphertextsBase64;
  final List<String> chunkHashesHex;

  const AttachmentManifest({
    required this.objectId,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.plaintextSha256Hex,
    required this.objectKeyBase64,
    required this.chunkCiphertextsBase64,
    required this.chunkHashesHex,
  });

  Map<String, dynamic> toJson() => {
        'objectId': objectId,
        'fileName': fileName,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'sha256': plaintextSha256Hex,
        'keyB64': objectKeyBase64,
        'chunks': chunkCiphertextsBase64,
        'chunkHashes': chunkHashesHex,
      };

  factory AttachmentManifest.fromJson(Map<String, dynamic> json) =>
      AttachmentManifest(
        objectId: json['objectId'] as String,
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        byteSize: (json['byteSize'] as num).toInt(),
        plaintextSha256Hex: json['sha256'] as String,
        objectKeyBase64: json['keyB64'] as String,
        chunkCiphertextsBase64:
            (json['chunks'] as List<dynamic>).cast<String>(),
        chunkHashesHex: (json['chunkHashes'] as List<dynamic>).cast<String>(),
      );
}

class CommittedInboundMessage {
  final String messageId;
  final String conversationId;
  final String senderPublicId;
  final String text;
  final int? expiresAtMs;
  final List<AttachmentManifest> attachments;

  const CommittedInboundMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderPublicId,
    required this.text,
    this.expiresAtMs,
    this.attachments = const [],
  });
}

class PollCommitResult {
  final int fetchedCount;
  final List<CommittedInboundMessage> committed;
  final int ackedCount;
  final int skippedDuplicateCount;
  final List<String> errors;

  const PollCommitResult({
    required this.fetchedCount,
    required this.committed,
    required this.ackedCount,
    required this.skippedDuplicateCount,
    this.errors = const [],
  });
}

/// Estágios de injeção controlada de falhas para verificação transacional (Fase 4).
enum MessagingFaultStage {
  beforeSessionSave,
  afterSessionSave,
  afterMessageInsert,
  duringOutboxInsert,
  duringRelaySend,
  afterRemoteAcceptBeforeLocalConfirm,
}

/// Motor real de mensageria E2EE, Outbox, Inbox Commit-before-ACK,
/// Anexos em chunks e Grupos com Sender Keys (Fase 3 / Gate 3).
class SovereignMessenger {
  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Hmac _hmacSha256 = Hmac.sha256();

  final LocalDatabase database;
  final NixIdentity identity;
  final String localDeviceId;
  final Uint8List vaultMasterKey;
  final String storageRootDir;

  late final IdentityRepository identityRepo = IdentityRepository(database);
  late final ContactRepository contactRepo = ContactRepository(database);
  late final ConversationRepository conversationRepo =
      ConversationRepository(database);
  late final MessageRepository messageRepo = MessageRepository(database);
  late final OutboxRepository outboxRepo = OutboxRepository(database);
  late final SessionRepository sessionRepo = SessionRepository(database);
  late final PreKeyRepository preKeyRepo = PreKeyRepository(database);
  late final KeyMaterialRepository keyMaterialRepo =
      KeyMaterialRepository(database);
  late final ObjectChunkRepository objectChunkRepo =
      ObjectChunkRepository(database);

  SovereignMessenger({
    required this.database,
    required this.identity,
    required this.vaultMasterKey,
    this.localDeviceId = 'dev_primary',
    String? storageRootDir,
  }) : storageRootDir = storageRootDir ?? _resolveDefaultStorageRootDir();

  /// Deriva credenciais de mailbox determinísticas para um `publicId` local.
  static MailboxCredentials deriveMailboxCredentials(String publicId) {
    final clean = publicId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final mbId = 'mbx_${clean.isEmpty ? "default" : clean}';
    final tokenDigest = std_crypto.sha256
        .convert(utf8.encode('nix-mailbox-capability-v1:$publicId'))
        .toString();
    return MailboxCredentials(
      mailboxId: mbId,
      readToken: 'read_$tokenDigest',
      writeQuotaToken: 'quota_$tokenDigest',
    );
  }

  static String _resolveDefaultStorageRootDir() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '${Directory.systemTemp.path}/nix_test_storage_$pid';
    }
    final dbParent = File(LocalDatabase.getDefaultDatabasePath()).parent.path;
    return '$dbParent/encrypted_objects';
  }

  Future<SecretKeyData> _deriveSessionWrapKey() async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(vaultMasterKey),
      nonce: utf8.encode('nix-messenger-session-v1'),
      info: utf8.encode('Nix-RatchetSessionWrap-v1'),
    );
    return derived.extract();
  }

  /// Gera e persiste uma SignedPreKey X25519 local assinada pela Ed25519 do usuário.
  Future<({SignedPreKeyBundle bundle, SimpleKeyPairData keyPair})>
      provisionSignedPreKey({
    String preKeyId = 'spk_active_1',
    Duration validFor = const Duration(days: 30),
  }) async {
    final kp = await _x25519.newKeyPair();
    final extracted = await kp.extract();
    final bundle = await SignedPreKeyBundle.create(
      owner: identity,
      signedPreKeyPair: extracted,
    );

    final wrapKey = await _deriveSessionWrapKey();
    final sealedPriv = await SealedEnvelope.seal(
      key: wrapKey,
      plaintext: extracted.bytes,
      aad: utf8.encode('prekey:$preKeyId'),
    );
    final keyRef = 'prekey:$preKeyId';
    await keyMaterialRepo.storeKeyMaterial(
      id: keyRef,
      purpose: 'signed_prekey_x25519',
      wrappedBytes: sealedPriv.encode(),
      wrappingKeyRef: 'keyvault:master',
    );
    await preKeyRepo.storePreKey(
      id: preKeyId,
      identityId: identity.publicId,
      deviceId: localDeviceId,
      kind: 'signed',
      publicBytes: Uint8List.fromList(bundle.signedPreKey.bytes),
      keyRef: keyRef,
      signature: Uint8List.fromList(bundle.signature),
      expiresAt: DateTime.now().toUtc().add(validFor).millisecondsSinceEpoch,
    );
    return (bundle: bundle, keyPair: extracted);
  }

  Future<SimpleKeyPairData?> loadSignedPreKey(String preKeyId) async {
    final row = await keyMaterialRepo.getKeyMaterial('prekey:$preKeyId');
    if (row == null) return null;
    final wrapKey = await _deriveSessionWrapKey();
    final clear = await SealedEnvelope.open(
      key: wrapKey,
      payload:
          SealedPayload.decode(Uint8List.fromList(row['wrapped_bytes'] as List<int>)),
      aad: utf8.encode('prekey:$preKeyId'),
    );
    final pair = await _x25519.newKeyPairFromSeed(clear);
    return pair.extract();
  }

  /// Exporta Card ID assinado via Ed25519 (JSON pronto para QR/cópia out-of-band).
  Future<String> exportSignedCardJson({
    required String displayName,
    required String mailboxId,
    required SignedPreKeyBundle preKeyBundle,
  }) async {
    final record = await SignedRecord.create(
      signer: identity,
      recordType: 'nix.card.v1',
      ttl: const Duration(days: 30),
      payload: {
        'publicId': identity.publicId,
        'displayName': displayName,
        'mailboxId': mailboxId,
        'ed25519': _toHex(identity.ed25519PublicKey.bytes),
        'x25519': _toHex(identity.x25519PublicKey.bytes),
        'spk': _toHex(preKeyBundle.signedPreKey.bytes),
        'spkSig': _toHex(preKeyBundle.signature),
      },
    );
    return jsonEncode({
      'recordType': record.recordType,
      'issuer': record.issuerEd25519Hex,
      'nonce': record.nonceHex,
      'iat': record.issuedAtEpochMs,
      'exp': record.expiresAtEpochMs,
      'payload': record.payload,
      'sig': record.signatureHex,
    });
  }

  /// Importa e valida assinatura Ed25519 de Card ID remoto, detectando mudanças de chave (MITM/rotação).
  Future<CardImportResult> importAndVerifyCardJson({
    required String rawJson,
    bool markVerifiedOutOfBand = true,
  }) async {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final record = SignedRecord(
        recordType: map['recordType'] as String,
        issuerEd25519Hex: map['issuer'] as String,
        nonceHex: map['nonce'] as String,
        issuedAtEpochMs: (map['iat'] as num).toInt(),
        expiresAtEpochMs: (map['exp'] as num).toInt(),
        payload: Map<String, dynamic>.from(map['payload'] as Map),
        signatureHex: map['sig'] as String,
      );

      final sigOk = await record.verify();
      if (!sigOk || record.recordType != 'nix.card.v1') {
        return const CardImportResult(
          status: CardImportStatus.invalidSignatureOrExpired,
          reason: 'Assinatura Ed25519 do Card ID inválida ou expirada.',
        );
      }

      final payload = record.payload;
      final publicId = payload['publicId'] as String;
      final displayName = payload['displayName'] as String? ?? publicId;
      final mailboxId = payload['mailboxId'] as String;
      final edBytes = _fromHex(payload['ed25519'] as String);
      final xBytes = _fromHex(payload['x25519'] as String);
      final spkBytes = _fromHex(payload['spk'] as String);
      final spkSig = _fromHex(payload['spkSig'] as String);

      // Valida também que a chave pública do payload bate com issuerEd25519Hex e que a SPK é assinada
      if ((payload['ed25519'] as String).toLowerCase() !=
          record.issuerEd25519Hex.toLowerCase()) {
        return const CardImportResult(
          status: CardImportStatus.invalidSignatureOrExpired,
          reason: 'Divergência entre assinante e Ed25519 do Card ID.',
        );
      }

      final spkBundle = SignedPreKeyBundle(
        identityEd25519: SimplePublicKey(edBytes, type: KeyPairType.ed25519),
        identityX25519: SimplePublicKey(xBytes, type: KeyPairType.x25519),
        signedPreKey: SimplePublicKey(spkBytes, type: KeyPairType.x25519),
        signature: spkSig,
      );
      if (!await spkBundle.verifySignature()) {
        return const CardImportResult(
          status: CardImportStatus.invalidSignatureOrExpired,
          reason: 'Assinatura da SignedPreKey X25519 do par é inválida.',
        );
      }

      final existing = await contactRepo.getContact(publicId);
      final bundleBytes = Uint8List.fromList(utf8.encode(rawJson));
      if (existing != null) {
        final prevEd = existing['ed_public'] as List<int>;
        final prevX = existing['x_public'] as List<int>;
        final keyChanged =
            !_constantTimeEq(prevEd, edBytes) || !_constantTimeEq(prevX, xBytes);
        if (keyChanged) {
          final history = await contactRepo.getKeyHistory(publicId);
          final nextVer =
              history.isEmpty ? 2 : ((history.first['version'] as int) + 1);
          await contactRepo.updateVerification(publicId, 'changed');
          await contactRepo.appendKeyHistory(
            contactId: publicId,
            version: nextVer,
            bundle: bundleBytes,
            acceptedAt: null,
          );
          return CardImportResult(
            status: CardImportStatus.keyChangedWarning,
            publicId: publicId,
            displayName: displayName,
            mailboxId: mailboxId,
            signedPreKeyBundle: spkBundle,
            reason:
                'ALERTA DE SEGURANÇA: A chave criptográfica do contato $publicId mudou!',
          );
        }
      }

      final verification =
          markVerifiedOutOfBand ? 'verified' : 'unverified';
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await contactRepo.upsertContact(
        id: publicId,
        edPublic: edBytes,
        xPublic: xBytes,
        fingerprint: publicId,
        displayName: displayName,
        verification: verification,
        verifiedAt: markVerifiedOutOfBand ? now : null,
      );
      final history = await contactRepo.getKeyHistory(publicId);
      if (history.isEmpty) {
        await contactRepo.appendKeyHistory(
          contactId: publicId,
          version: 1,
          bundle: bundleBytes,
          acceptedAt: markVerifiedOutOfBand ? now : null,
        );
      }

      return CardImportResult(
        status: markVerifiedOutOfBand
            ? CardImportStatus.importedVerified
            : CardImportStatus.importedUnverified,
        publicId: publicId,
        displayName: displayName,
        mailboxId: mailboxId,
        signedPreKeyBundle: spkBundle,
      );
    } catch (e) {
      return CardImportResult(
        status: CardImportStatus.invalidSignatureOrExpired,
        reason: 'Card ID malformado ou falha de validação: $e',
      );
    }
  }

  /// Inicia sessão Double Ratchet via X3DH (Lado Iniciador / Alice) e persiste estado no SQLCipher.
  Future<void> establishInitiatorSession({
    required String conversationId,
    required String peerPublicId,
    required String peerDeviceId,
    required SignedPreKeyBundle peerBundle,
    String peerTitle = '',
    String? peerMailbox,
  }) async {
    final existingConv = await conversationRepo.getConversation(conversationId);
    if (existingConv == null) {
      await conversationRepo.createConversation(
        id: conversationId,
        kind: 'direct',
        ownerIdentityId: identity.publicId,
        title: peerTitle.isEmpty ? peerPublicId : peerTitle,
      );
    }

    final x3dhRes = await X3dh.initiatorDerive(
      initiatorIdentity: identity,
      responderBundle: peerBundle,
    );
    final ratchet = await DoubleRatchet.initInitiator(
      sharedSecret: x3dhRes.sharedSecret,
      responderRatchetPublicKey: peerBundle.signedPreKey,
    );

    final stateObj = <String, dynamic>{
      'ratchet': ratchet.exportState(),
      'needsHandshake': true,
      'initiatorX25519': _toHex(identity.x25519PublicKey.bytes),
      'initiatorEd25519': _toHex(identity.ed25519PublicKey.bytes),
      'ekPubHex': _toHex(x3dhRes.ephemeralKeyPair.publicKey.bytes),
      'peerPublicId': peerPublicId,
      'peerSpkHex': _toHex(peerBundle.signedPreKey.bytes),
      if (peerMailbox != null) 'peerMailbox': peerMailbox,
    };

    await _saveEncryptedSession(
      sessionId: 'sess_${conversationId}_$peerDeviceId',
      conversationId: conversationId,
      peerDeviceId: peerDeviceId,
      stateObj: stateObj,
      revision: 1,
    );
  }

  /// Retorna metadados decifrados da sessão (`peerPublicId`, `peerMailbox`, `needsHandshake`) se existir.
  Future<Map<String, dynamic>?> getSessionMetadata(String conversationId) async {
    final loaded = await _loadEncryptedSession(conversationId);
    if (loaded == null) return null;
    return loaded.$2;
  }

  Future<void> _saveEncryptedSession({
    required String sessionId,
    required String conversationId,
    required String peerDeviceId,
    required Map<String, dynamic> stateObj,
    required int revision,
  }) async {
    final wrapKey = await _deriveSessionWrapKey();
    final sealed = await SealedEnvelope.seal(
      key: wrapKey,
      plaintext: utf8.encode(jsonEncode(stateObj)),
      aad: utf8.encode('sess:$conversationId:$peerDeviceId'),
    );
    await sessionRepo.saveSession(
      id: sessionId,
      conversationId: conversationId,
      localDeviceId: localDeviceId,
      peerDeviceId: peerDeviceId,
      stateBlob: sealed.encode(),
      revision: revision,
    );
  }

  Future<(Map<String, dynamic>, Map<String, dynamic>)?> _loadEncryptedSession(
    String conversationId,
  ) async {
    final row = await sessionRepo.getSessionByConversation(conversationId);
    if (row == null) return null;
    final peerDeviceId = row['peer_device_id'] as String;
    final wrapKey = await _deriveSessionWrapKey();
    final sealed = SealedPayload.decode(
      Uint8List.fromList(row['state_blob'] as List<int>),
    );
    final clear = await SealedEnvelope.open(
      key: wrapKey,
      payload: sealed,
      aad: utf8.encode('sess:$conversationId:$peerDeviceId'),
    );
    return (
      row,
      jsonDecode(utf8.decode(clear)) as Map<String, dynamic>,
    );
  }

  /// Divide um anexo binário em chunks cifrados com XChaCha20-Poly1305 e grava localmente.
  /// Imagens passam obrigatoriamente por remoção de metadados (EXIF/chunks).
  /// Suporta cancelamento cooperativo via [isCancelled] com limpeza automática de chunks parciais.
  Future<AttachmentManifest> prepareEncryptedAttachment({
    required String fileName,
    required String mimeType,
    required Uint8List rawBytes,
    int chunkSize = 65536,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) {
      throw StateError('Preparação de anexo cancelada antes do início.');
    }
    var cleanBytes = rawBytes;
    if (LocalImageHelper.isSupportedExtension(fileName)) {
      cleanBytes = LocalImageHelper.stripMetadataBytes(rawBytes);
    }

    final objectId =
        'obj_${DateTime.now().toUtc().millisecondsSinceEpoch}_${_toHex(SecretKeyData.random(length: 6).bytes)}';
    final objKeyData = SecretKeyData.random(length: 32);
    final digest =
        Uint8List.fromList(std_crypto.sha256.convert(cleanBytes).bytes);

    final baseObjDir = Directory('$storageRootDir/objects');
    await baseObjDir.create(recursive: true);
    final manifestPath = '${baseObjDir.path}/$objectId.manifest';
    final writtenPaths = <String>[];

    final chunksB64 = <String>[];
    final chunkHashes = <String>[];
    int chunkNo = 0;

    try {
      await objectChunkRepo.upsertObject(
        id: objectId,
        sha256Digest: digest,
        mimeType: mimeType,
        byteSize: cleanBytes.length,
        keyRef: 'object_inline:$objectId',
        encryptedPath: manifestPath,
      );

      if (cleanBytes.isEmpty) {
        if (isCancelled?.call() == true) {
          throw StateError('Preparação de anexo cancelada.');
        }
        final sealed = await SealedEnvelope.seal(
          key: objKeyData,
          plaintext: const [],
          aad: utf8.encode('nix-chunk:$objectId:0'),
        );
        final encoded = sealed.encode();
        final cHash = Uint8List.fromList(std_crypto.sha256.convert(encoded).bytes);
        final chunkPath = '${baseObjDir.path}/$objectId.0.chk';
        await File(chunkPath).writeAsBytes(encoded, flush: true);
        writtenPaths.add(chunkPath);
        await objectChunkRepo.upsertChunk(
          objectId: objectId,
          chunkNo: 0,
          ciphertextHash: cHash,
          cipherSize: encoded.length,
          encryptedPath: chunkPath,
        );
        chunksB64.add(base64Encode(encoded));
        chunkHashes.add(_toHex(cHash));
      } else {
        for (int offset = 0; offset < cleanBytes.length; offset += chunkSize) {
          if (isCancelled?.call() == true) {
            throw StateError('Preparação de anexo cancelada durante fragmentação.');
          }
          final end = (offset + chunkSize > cleanBytes.length)
              ? cleanBytes.length
              : offset + chunkSize;
          final slice = cleanBytes.sublist(offset, end);
          final sealed = await SealedEnvelope.seal(
            key: objKeyData,
            plaintext: slice,
            aad: utf8.encode('nix-chunk:$objectId:$chunkNo'),
          );
          final encoded = sealed.encode();
          final cHash =
              Uint8List.fromList(std_crypto.sha256.convert(encoded).bytes);
          final chunkPath = '${baseObjDir.path}/$objectId.$chunkNo.chk';
          await File(chunkPath).writeAsBytes(encoded, flush: true);
          writtenPaths.add(chunkPath);
          await objectChunkRepo.upsertChunk(
            objectId: objectId,
            chunkNo: chunkNo,
            ciphertextHash: cHash,
            cipherSize: encoded.length,
            encryptedPath: chunkPath,
          );
          chunksB64.add(base64Encode(encoded));
          chunkHashes.add(_toHex(cHash));
          chunkNo++;
        }
      }

      final manifest = AttachmentManifest(
        objectId: objectId,
        fileName: fileName,
        mimeType: mimeType,
        byteSize: cleanBytes.length,
        plaintextSha256Hex: _toHex(digest),
        objectKeyBase64: base64Encode(objKeyData.bytes),
        chunkCiphertextsBase64: chunksB64,
        chunkHashesHex: chunkHashes,
      );
      await File(manifestPath).writeAsString(jsonEncode(manifest.toJson()), flush: true);
      writtenPaths.add(manifestPath);
      return manifest;
    } catch (_) {
      await cleanupTemporaryStagingFiles(writtenPaths);
      try {
        await database.rawDatabase.delete('object_chunks', where: 'object_id = ?', whereArgs: [objectId]);
        await database.rawDatabase.delete('objects', where: 'id = ?', whereArgs: [objectId]);
      } catch (_) {}
      rethrow;
    }
  }

  /// Remove arquivos temporários de staging após envio ou cancelamento.
  Future<int> cleanupTemporaryStagingFiles(List<String> paths) async {
    int deleted = 0;
    for (final p in paths) {
      if (p.trim().isEmpty) continue;
      final f = File(p);
      if (await f.exists()) {
        try {
          await f.delete();
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }

  /// Verifica integridade de todos os chunks + SHA-256 global e remonta os bytes originais.
  Future<Uint8List> decryptAndReassembleAttachment(
    AttachmentManifest manifest,
  ) async {
    final keyData = SecretKeyData(base64Decode(manifest.objectKeyBase64));
    final builder = BytesBuilder(copy: false);
    for (int i = 0; i < manifest.chunkCiphertextsBase64.length; i++) {
      final cipherBytes = base64Decode(manifest.chunkCiphertextsBase64[i]);
      final expectedChunkHash = manifest.chunkHashesHex[i];
      final actualChunkHash =
          _toHex(std_crypto.sha256.convert(cipherBytes).bytes);
      if (actualChunkHash != expectedChunkHash) {
        throw StateError('Hash de integridade do chunk $i divergente.');
      }
      final clearChunk = await SealedEnvelope.open(
        key: keyData,
        payload: SealedPayload.decode(cipherBytes),
        aad: utf8.encode('nix-chunk:${manifest.objectId}:$i'),
      );
      builder.add(clearChunk);
    }
    final joined = builder.toBytes();
    final actualSha = _toHex(std_crypto.sha256.convert(joined).bytes);
    if (actualSha != manifest.plaintextSha256Hex) {
      throw StateError('SHA-256 final do anexo divergente do manifesto.');
    }
    return joined;
  }

  /// Cifra via Double Ratchet e persiste `sessions`, `messages`, `message_attachments` e `outbox`
  /// dentro de uma ÚNICA transação SQLite atômica (Fase 4).
  /// Qualquer falha em [onFaultStage] ou erro de banco desfaz todas as gravações sem avançar a sessão.
  Future<({String messageId, String outboxId})> enqueueDirectMessage({
    required String conversationId,
    required String destinationMailbox,
    required String senderMailbox,
    required String text,
    int? ephemeralTtlSeconds,
    List<AttachmentManifest> attachments = const [],
    void Function(MessagingFaultStage stage)? onFaultStage,
  }) async {
    final loaded = await _loadEncryptedSession(conversationId);
    if (loaded == null) {
      throw StateError('Sessão Double Ratchet não encontrada para $conversationId.');
    }
    final row = loaded.$1;
    final stateObj = Map<String, dynamic>.from(loaded.$2);
    final ratchet = await DoubleRatchet.importState(
      Map<String, dynamic>.from(stateObj['ratchet'] as Map),
    );

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final expiresAtMs = (ephemeralTtlSeconds != null && ephemeralTtlSeconds > 0)
        ? nowMs + (ephemeralTtlSeconds * 1000)
        : null;
    final msgId =
        'msg_${nowMs}_${_toHex(SecretKeyData.random(length: 4).bytes)}';
    final outboxId =
        'out_${nowMs}_${_toHex(SecretKeyData.random(length: 4).bytes)}';

    final innerPayload = jsonEncode({
      'id': msgId,
      'convId': conversationId,
      'sender': identity.publicId,
      'text': text,
      'ts': nowMs,
      if (expiresAtMs != null) 'expiresAt': expiresAtMs,
      if (ephemeralTtlSeconds != null && ephemeralTtlSeconds > 0)
        'ttlSec': ephemeralTtlSeconds,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
    });

    final aad = utf8.encode('nix-e2ee-v1:$conversationId');
    final cipher = await ratchet.encrypt(
      utf8.encode(innerPayload),
      extraAad: aad,
    );

    final includeHandshake = (stateObj['needsHandshake'] as bool?) == true;
    final wireEnvelope = <String, dynamic>{
      'v': 1,
      'msgId': msgId,
      'convId': conversationId,
      'sender': identity.publicId,
      'senderMailbox': senderMailbox,
      'ratchetB64': base64Encode(cipher.encode()),
      if (includeHandshake)
        'x3dh': {
          'ikXHex': stateObj['initiatorX25519'],
          'ikEdHex': stateObj['initiatorEd25519'],
          'ekPubHex': stateObj['ekPubHex'],
        },
    };
    final wireBytes = Uint8List.fromList(utf8.encode(jsonEncode(wireEnvelope)));

    // Prepara o blob cifrado da sessão candidata em memória antes de abrir a transação
    stateObj['ratchet'] = ratchet.exportState();
    final sessionId = row['id'] as String;
    final peerDeviceId = row['peer_device_id'] as String;
    final nextRev = (row['revision'] as int? ?? 0) + 1;
    final wrapKey = await _deriveSessionWrapKey();
    final sealedSession = await SealedEnvelope.seal(
      key: wrapKey,
      plaintext: utf8.encode(jsonEncode(stateObj)),
      aad: utf8.encode('sess:$conversationId:$peerDeviceId'),
    );
    final payloadHash =
        Uint8List.fromList(std_crypto.sha256.convert(wireBytes).bytes);
    final outboxExpiresAt = nowMs + const Duration(days: 7).inMilliseconds;

    // Transação atômica: ou grava sessão + mensagem + anexos + outbox juntos, ou faz rollback completo!
    await database.rawDatabase.transaction((txn) async {
      onFaultStage?.call(MessagingFaultStage.beforeSessionSave);

      await txn.rawInsert('''
        INSERT OR REPLACE INTO sessions(
          id, conversation_id, local_device_id, peer_device_id,
          state_blob, format_version, revision, updated_at
        ) VALUES (?, ?, ?, ?, ?, 1, ?, ?);
      ''', [
        sessionId,
        conversationId,
        localDeviceId,
        peerDeviceId,
        sealedSession.encode(),
        nextRev,
        nowMs,
      ]);

      onFaultStage?.call(MessagingFaultStage.afterSessionSave);

      await txn.rawInsert('''
        INSERT INTO messages(
          id, conversation_id, author_key, device_id, body,
          created_at, expires_at, revision, delivery_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'queued');
      ''', [
        msgId,
        conversationId,
        identity.publicId,
        localDeviceId,
        text,
        nowMs,
        expiresAtMs,
      ]);

      onFaultStage?.call(MessagingFaultStage.afterMessageInsert);

      for (int i = 0; i < attachments.length; i++) {
        await txn.rawInsert('''
          INSERT OR REPLACE INTO attachments(
            message_id, object_id, file_name, ordinal
          ) VALUES (?, ?, ?, ?);
        ''', [
          msgId,
          attachments[i].objectId,
          attachments[i].fileName,
          i,
        ]);
      }

      onFaultStage?.call(MessagingFaultStage.duringOutboxInsert);

      await txn.rawInsert('''
        INSERT INTO outbox(
          id, message_id, session_id, destination_mailbox,
          ciphertext, payload_hash, transport_state, attempts,
          next_attempt_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, 'queued', 0, 0, ?);
      ''', [
        outboxId,
        msgId,
        sessionId,
        destinationMailbox,
        wireBytes,
        payloadHash,
        outboxExpiresAt,
      ]);
    });

    return (messageId: msgId, outboxId: outboxId);
  }

  /// Drena a Outbox persistente pelo `RelayClient` preservando o mesmo `ciphertext` em retentativas.
  Future<({int accepted, int failed})> flushOutbox({
    required RelayClient relayClient,
    String? quotaToken,
    int retryDelayMs = 2000,
    void Function(MessagingFaultStage stage)? onFaultStage,
  }) async {
    final pending = await outboxRepo.getPendingEnvelopes(limit: 50);
    int accepted = 0;
    int failed = 0;

    for (final row in pending) {
      final outboxId = row['id'] as String;
      final destMailbox = row['destination_mailbox'] as String;
      final msgId = row['message_id'] as String?;
      final cipher = Uint8List.fromList(row['ciphertext'] as List<int>);
      try {
        onFaultStage?.call(MessagingFaultStage.duringRelaySend);
        final relayEnvId = await relayClient.storeEnvelope(
          mailboxId: destMailbox,
          cipherPayload: cipher,
          quotaToken: quotaToken,
        );
        onFaultStage?.call(MessagingFaultStage.afterRemoteAcceptBeforeLocalConfirm);
        await database.rawDatabase.transaction((txn) async {
          await txn.update(
            'outbox',
            {
              'transport_state': 'accepted',
              'relay_envelope_id': relayEnvId,
            },
            where: 'id = ?',
            whereArgs: [outboxId],
          );
          if (msgId != null) {
            await txn.update(
              'messages',
              {'delivery_state': 'accepted'},
              where: 'id = ?',
              whereArgs: [msgId],
            );
          }
        });
        accepted++;
      } catch (_) {
        final nextRetry =
            DateTime.now().toUtc().millisecondsSinceEpoch + retryDelayMs;
        await database.rawDatabase.transaction((txn) async {
          await txn.rawUpdate('''
            UPDATE outbox
            SET transport_state = 'failed',
                attempts = attempts + 1,
                next_attempt_at = ?
            WHERE id = ?;
          ''', [nextRetry, outboxId]);
          if (msgId != null) {
            await txn.update(
              'messages',
              {'delivery_state': 'failed'},
              where: 'id = ? AND delivery_state != ?',
              whereArgs: [msgId, 'accepted'],
            );
          }
        });
        failed++;
      }
    }
    return (accepted: accepted, failed: failed);
  }

  /// Busca envelopes no relay, decifra via X3DH/DoubleRatchet, commita `messages` + `sessions` + `inbox_dedup`
  /// antes do `ACK`, e só remove do relay após o commit local em SQLCipher.
  Future<PollCommitResult> pollAndCommitInbox({
    required MailboxCredentials creds,
    required RelayClient relayClient,
    String preKeyId = 'spk_active_1',
    bool simulateCrashBeforeAck = false,
  }) async {
    return _commitInbox(
      mailboxId: creds.mailboxId,
      envelopes: await relayClient.fetchEnvelopes(creds),
      preKeyId: preKeyId,
      acknowledge: simulateCrashBeforeAck
          ? null
          : (ids) => relayClient.acknowledge(creds, ids),
    );
  }

  static List<int> _nearbyAad(
    String mailboxId,
    String deliveryId,
    int expiresAtMs,
  ) => utf8.encode('nix-nearby-v1:$mailboxId:$deliveryId:$expiresAtMs');

  /// Cifra também os metadados do envelope Ratchet para a chave do contato.
  Future<Uint8List> sealNearbyDelivery({
    required String peerPublicId,
    required String mailboxId,
    required String deliveryId,
    required Uint8List wireBytes,
    required int expiresAtMs,
  }) async {
    final contact = await contactRepo.getContact(peerPublicId);
    if (contact == null || contact['verification'] == 'changed') {
      throw StateError('O contato BLE requer um Card ID válido.');
    }
    final ephemeral = await _x25519.newKeyPair();
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        contact['x_public'] as List<int>,
        type: KeyPairType.x25519,
      ),
    );
    final aad = _nearbyAad(mailboxId, deliveryId, expiresAtMs);
    final key = await _hkdf.deriveKey(secretKey: shared, info: aad);
    final signature = await identity.sign([...aad, ...wireBytes]);
    final sealed = await SealedEnvelope.seal(
      key: key,
      plaintext: [...signature, ...wireBytes],
      aad: aad,
    );
    final publicKey = await ephemeral.extractPublicKey();
    return Uint8List.fromList([...publicKey.bytes, ...sealed.encode()]);
  }

  Future<PollCommitResult> commitNearbyDelivery({
    required String mailboxId,
    required String deliveryId,
    required Uint8List ciphertext,
    required int expiresAtMs,
    String preKeyId = 'spk_active_1',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (expiresAtMs <= now ||
        ciphertext.length <= 32 ||
        ciphertext.length > 34 * 1024) {
      throw const FormatException('Envelope BLE expirado ou incompleto.');
    }
    final aad = _nearbyAad(mailboxId, deliveryId, expiresAtMs);
    final shared = await _x25519.sharedSecretKey(
      keyPair: identity.x25519KeyPair,
      remotePublicKey: SimplePublicKey(
        ciphertext.sublist(0, 32),
        type: KeyPairType.x25519,
      ),
    );
    final key = await _hkdf.deriveKey(secretKey: shared, info: aad);
    final signedWire = await SealedEnvelope.open(
      key: key,
      payload: SealedPayload.decode(ciphertext.sublist(32)),
      aad: aad,
    );
    if (signedWire.length <= 64) {
      throw const FormatException('Assinatura BLE incompleta.');
    }
    final wire = signedWire.sublist(64);
    final header = jsonDecode(utf8.decode(wire)) as Map<String, dynamic>;
    final contact = await contactRepo.getContact(header['sender'] as String);
    if (contact == null || contact['verification'] == 'changed') {
      throw const FormatException('Remetente BLE sem Card ID válido.');
    }
    final valid = await Ed25519().verify(
      [...aad, ...wire],
      signature: Signature(
        signedWire.sublist(0, 64),
        publicKey: SimplePublicKey(
          contact['ed_public'] as List<int>,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const FormatException('Assinatura BLE inválida.');

    return _commitInbox(
      mailboxId: mailboxId,
      preKeyId: preKeyId,
      nearbyOnly: true,
      envelopes: [
        RelayEnvelope(
          id: deliveryId,
          payloadBase64: base64Encode(wire),
          createdAtUnix: now ~/ 1000,
          expiresAtUnix: expiresAtMs ~/ 1000,
        ),
      ],
    );
  }

  Future<PollCommitResult> _commitInbox({
    required String mailboxId,
    required List<RelayEnvelope> envelopes,
    required String preKeyId,
    Future<int> Function(List<String>)? acknowledge,
    bool nearbyOnly = false,
  }) async {
    final committed = <CommittedInboundMessage>[];
    final ackIds = <String>[];
    final errors = <String>[];
    int skippedDuplicates = 0;

    for (final env in envelopes) {
      // 1. Deduplicação: se já commitamos este envelope antes (ex: queda pré-ACK), apenas re-confirma no relay
      if (await outboxRepo.isDuplicateEnvelope(mailboxId, env.id)) {
        skippedDuplicates++;
        ackIds.add(env.id);
        continue;
      }

      try {
        final rawBytes = base64Decode(env.payloadBase64);
        final wire =
            jsonDecode(utf8.decode(rawBytes)) as Map<String, dynamic>;
        final convId = wire['convId'] as String;
        final senderId = wire['sender'] as String;
        final wireMsgId = wire['msgId'] as String?;
        final ratchetBytes = base64Decode(wire['ratchetB64'] as String);
        final cipher = RatchetCiphertext.decode(ratchetBytes);

        // 1b. Deduplicação por msgId (quando remetente retransmitiu mesmo ciphertext após falha pós-POST)
        if (wireMsgId != null) {
          final existingMsg = await database.rawDatabase.query(
            'messages',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [wireMsgId],
            limit: 1,
          );
          if (existingMsg.isNotEmpty) {
            final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
            final payloadHash =
                Uint8List.fromList(std_crypto.sha256.convert(rawBytes).bytes);
            await outboxRepo.recordDeduplication(
              mailboxId: mailboxId,
              deliveryId: env.id,
              payloadHash: payloadHash,
              expiresAt: nowMs + const Duration(days: 7).inMilliseconds,
            );
            skippedDuplicates++;
            ackIds.add(env.id);
            continue;
          }
        }

        // Valida que remetente não sofreu alteração silenciosa de chave
        final contact = await contactRepo.getContact(senderId);
        if (nearbyOnly && contact == null) {
          errors.add('Envelope BLE de contato sem Card ID importado.');
          continue;
        }
        if (contact != null && contact['verification'] == 'changed') {
          errors.add('Bloqueado envelope de $senderId: chave marcada como alterada.');
          continue;
        }

        // Carrega ou cria sessão respondedora via X3DH
        Map<String, dynamic>? loadedSessionRow;
        Map<String, dynamic>? stateObj;
        DoubleRatchet? ratchet;
        final existing = await _loadEncryptedSession(convId);

        if (existing != null) {
          loadedSessionRow = existing.$1;
          stateObj = existing.$2;
          if (nearbyOnly && stateObj['peerPublicId'] != senderId) {
            errors.add('Remetente BLE não corresponde à sessão.');
            continue;
          }
          ratchet = await DoubleRatchet.importState(
            Map<String, dynamic>.from(stateObj['ratchet'] as Map),
          );
          if ((stateObj['needsHandshake'] as bool?) == true) {
            stateObj['needsHandshake'] = false;
          }
        } else {
          final x3dhMap = wire['x3dh'] as Map<String, dynamic>?;
          if (x3dhMap == null) {
            errors.add('Envelope para $convId sem sessão nem cabeçalho X3DH.');
            continue;
          }
          final ikX = SimplePublicKey(
            _fromHex(x3dhMap['ikXHex'] as String),
            type: KeyPairType.x25519,
          );
          final ekPub = SimplePublicKey(
            _fromHex(x3dhMap['ekPubHex'] as String),
            type: KeyPairType.x25519,
          );
          if (contact != null &&
              !_constantTimeEq(contact['x_public'] as List<int>, ikX.bytes)) {
            errors.add('X3DH IK não confere com chave verificada do contato $senderId.');
            continue;
          }
          final spkPair = await loadSignedPreKey(preKeyId);
          if (spkPair == null) {
            errors.add('SignedPreKey local ($preKeyId) ausente para responder X3DH.');
            continue;
          }
          final sharedSecret = await X3dh.responderDerive(
            responderIdentity: identity,
            responderSignedPreKey: spkPair,
            initiatorX25519Identity: ikX,
            initiatorEphemeralPublicKey: ekPub,
          );
          ratchet = await DoubleRatchet.initResponder(
            sharedSecret: sharedSecret,
            responderRatchetKeyPair: spkPair,
          );
          stateObj = <String, dynamic>{
            'needsHandshake': false,
            'peerPublicId': senderId,
          };
        }

        // 2. Decifra e autentica AEAD antes de tocar o banco
        final clearBytes = await ratchet.decrypt(
          cipher,
          extraAad: utf8.encode('nix-e2ee-v1:$convId'),
        );
        final inner =
            jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
        final msgId = inner['id'] as String? ??
            'in_${DateTime.now().toUtc().millisecondsSinceEpoch}_${env.id}';
        final text = inner['text'] as String? ?? '';
        final createdAt = (inner['ts'] as num?)?.toInt() ??
            DateTime.now().toUtc().millisecondsSinceEpoch;
        final expiresAt = (inner['expiresAt'] as num?)?.toInt();
        if (nearbyOnly &&
            (inner['sender'] != senderId ||
                inner['convId'] != convId ||
                inner['id'] != wireMsgId ||
                (expiresAt != null &&
                    expiresAt <= DateTime.now().millisecondsSinceEpoch))) {
          errors.add('Envelope BLE expirado ou incompatível com a sessão.');
          continue;
        }

        final parsedAttachments = <AttachmentManifest>[];
        if (inner['attachments'] is List) {
          for (final a in (inner['attachments'] as List)) {
            parsedAttachments.add(
              AttachmentManifest.fromJson(Map<String, dynamic>.from(a as Map)),
            );
          }
        }

        if (wire['senderMailbox'] is String) {
          stateObj['peerMailbox'] = wire['senderMailbox'] as String;
        }
        stateObj['ratchet'] = ratchet.exportState();
        final wrapKey = await _deriveSessionWrapKey();
        final effectivePeerId =
            (loadedSessionRow?['peer_device_id'] as String?) ?? senderId;
        final sessionId = loadedSessionRow != null
            ? loadedSessionRow['id'] as String
            : 'sess_${convId}_$effectivePeerId';
        final sealedSession = await SealedEnvelope.seal(
          key: wrapKey,
          plaintext: utf8.encode(jsonEncode(stateObj)),
          aad: utf8.encode('sess:$convId:$effectivePeerId'),
        );
        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        final payloadHash =
            Uint8List.fromList(std_crypto.sha256.convert(rawBytes).bytes);
        final nextRev =
            (loadedSessionRow?['revision'] as int? ?? 0) + 1;

        // 3. COMMIT-BEFORE-ACK: conversa, sessão, mensagem e inbox_dedup na mesma transação!
        await database.rawDatabase.transaction((txn) async {
          final convExists = await txn.query(
            'conversations',
            where: 'id = ?',
            whereArgs: [convId],
            limit: 1,
          );
          if (convExists.isEmpty) {
            await txn.insert('conversations', {
              'id': convId,
              'kind': 'direct',
              'owner_identity_id': identity.publicId,
              'title': senderId,
              'epoch': 0,
              'created_at': nowMs,
              'updated_at': nowMs,
            });
          }

          await txn.rawInsert('''
            INSERT OR REPLACE INTO sessions(
              id, conversation_id, local_device_id, peer_device_id,
              state_blob, format_version, revision, updated_at
            ) VALUES (?, ?, ?, ?, ?, 1, ?, ?);
          ''', [
            sessionId,
            convId,
            localDeviceId,
            effectivePeerId,
            sealedSession.encode(),
            nextRev,
            nowMs,
          ]);

          await txn.rawInsert('''
            INSERT OR IGNORE INTO messages(
              id, conversation_id, author_key, device_id, body,
              created_at, received_at, expires_at, revision, delivery_state
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 'received');
          ''', [
            msgId,
            convId,
            senderId,
            senderId,
            text,
            createdAt,
            nowMs,
            expiresAt,
          ]);

          for (int i = 0; i < parsedAttachments.length; i++) {
            final att = parsedAttachments[i];
            final shaBytes = _fromHex(att.plaintextSha256Hex);
            await txn.rawInsert('''
              INSERT OR REPLACE INTO objects(
                id, sha256, mime_type, byte_size, key_ref, encrypted_path, created_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?);
            ''', [
              att.objectId,
              shaBytes,
              att.mimeType,
              att.byteSize,
              'object_inline:${att.objectId}',
              '$storageRootDir/objects/${att.objectId}_${msgId}_$i.manifest',
              nowMs,
            ]);
            await txn.rawInsert('''
              INSERT OR REPLACE INTO attachments(
                message_id, object_id, file_name, ordinal
              ) VALUES (?, ?, ?, ?);
            ''', [
              msgId,
              att.objectId,
              att.fileName,
              i,
            ]);
          }

          await txn.rawInsert('''
            INSERT OR IGNORE INTO inbox_dedup(
              mailbox_id, delivery_id, payload_hash, committed_at, expires_at
            ) VALUES (?, ?, ?, ?, ?);
          ''', [
            mailboxId,
            env.id,
            payloadHash,
            nowMs,
            nowMs + const Duration(days: 7).inMilliseconds,
          ]);
        });

        committed.add(CommittedInboundMessage(
          messageId: msgId,
          conversationId: convId,
          senderPublicId: senderId,
          text: text,
          expiresAtMs: expiresAt,
          attachments: parsedAttachments,
        ));
        ackIds.add(env.id);
      } catch (e) {
        errors.add('Falha no envelope ${env.id}: $e');
      }
    }

    int ackedCount = 0;
    if (acknowledge != null && ackIds.isNotEmpty) {
      ackedCount = await acknowledge(ackIds);
    }

    return PollCommitResult(
      fetchedCount: envelopes.length,
      committed: committed,
      ackedCount: ackedCount,
      skippedDuplicateCount: skippedDuplicates,
      errors: errors,
    );
  }

  /// ============= GRUPOS SENDER KEYS + ROTAÇÃO DE ÉPOCA =============

  /// Cria ou rotaciona época do grupo distribuindo nova Sender Key cifrada apenas para membros ativos.
  Future<({int epoch, Map<String, Uint8List> keyDistributionEnvelopes})>
      createOrRotateGroupEpoch({
    required String groupId,
    required String title,
    required List<({String publicId, SimplePublicKey x25519PublicKey})>
        activeMembers,
    String? removeMemberPublicId,
  }) async {
    final existing = await conversationRepo.getConversation(groupId);
    final newEpoch = existing == null ? 1 : ((existing['epoch'] as int) + 1);

    if (existing == null) {
      await conversationRepo.createConversation(
        id: groupId,
        kind: 'group',
        ownerIdentityId: identity.publicId,
        title: title,
        epoch: newEpoch,
      );
    } else {
      await conversationRepo.updateConversationEpoch(groupId, newEpoch);
    }

    if (removeMemberPublicId != null) {
      await conversationRepo.removeMember(
        conversationId: groupId,
        memberKey: removeMemberPublicId,
        deviceId: 'dev_primary',
        leftEpoch: newEpoch,
      );
    }

    final remaining = activeMembers
        .where((m) => m.publicId != removeMemberPublicId)
        .toList();

    for (final member in remaining) {
      await conversationRepo.addMember(
        conversationId: groupId,
        memberKey: member.publicId,
        deviceId: 'dev_primary',
        role: member.publicId == identity.publicId ? 'owner' : 'member',
        joinedEpoch: newEpoch,
      );
    }

    // Nova Sender Key CSPRNG de 32 bytes para o remetente neste epoch
    final senderKey = Uint8List.fromList(SecretKeyData.random(length: 32).bytes);
    await _saveGroupSenderKey(
      groupId: groupId,
      senderPublicId: identity.publicId,
      epoch: newEpoch,
      chainKey: senderKey,
      messageNo: 0,
    );

    // Embrulha a nova Sender Key com ECDH efêmero X25519 individualmente apenas para membros restantes
    final distribution = <String, Uint8List>{};
    for (final member in remaining) {
      final ephem = await _x25519.newKeyPair();
      final ephemPub = await ephem.extractPublicKey();
      final shared = await _x25519.sharedSecretKey(
        keyPair: ephem,
        remotePublicKey: member.x25519PublicKey,
      );
      final sealed = await SealedEnvelope.seal(
        key: shared,
        plaintext: utf8.encode(jsonEncode({
          'groupId': groupId,
          'epoch': newEpoch,
          'sender': identity.publicId,
          'chainKeyB64': base64Encode(senderKey),
        })),
        aad: utf8.encode('nix-group-sk:$groupId:$newEpoch'),
      );
      distribution[member.publicId] = Uint8List.fromList(
        utf8.encode(jsonEncode({
          'ephemHex': _toHex(ephemPub.bytes),
          'sealedB64': base64Encode(sealed.encode()),
        })),
      );
    }

    return (epoch: newEpoch, keyDistributionEnvelopes: distribution);
  }

  /// Recebe e instala localmente a Sender Key de um remetente para o epoch específico.
  Future<void> acceptGroupSenderKeyDistribution({
    required String groupId,
    required int expectedEpoch,
    required String senderPublicId,
    required NixIdentity recipientIdentity,
    required Uint8List distributionEnvelope,
  }) async {
    final map =
        jsonDecode(utf8.decode(distributionEnvelope)) as Map<String, dynamic>;
    final ephemPub = SimplePublicKey(
      _fromHex(map['ephemHex'] as String),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: recipientIdentity.x25519KeyPair,
      remotePublicKey: ephemPub,
    );
    final clear = await SealedEnvelope.open(
      key: shared,
      payload: SealedPayload.decode(base64Decode(map['sealedB64'] as String)),
      aad: utf8.encode('nix-group-sk:$groupId:$expectedEpoch'),
    );
    final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final chainKey = base64Decode(payload['chainKeyB64'] as String);
    await _saveGroupSenderKey(
      groupId: groupId,
      senderPublicId: senderPublicId,
      epoch: expectedEpoch,
      chainKey: Uint8List.fromList(chainKey),
      messageNo: 0,
    );
  }

  Future<void> _saveGroupSenderKey({
    required String groupId,
    required String senderPublicId,
    required int epoch,
    required Uint8List chainKey,
    required int messageNo,
  }) async {
    final wrapKey = await _deriveSessionWrapKey();
    final id = 'grp:${groupId}_ep${epoch}_$senderPublicId';
    final sealed = await SealedEnvelope.seal(
      key: wrapKey,
      plaintext: utf8.encode(jsonEncode({
        'chainKeyB64': base64Encode(chainKey),
        'msgNo': messageNo,
      })),
      aad: utf8.encode(id),
    );
    await keyMaterialRepo.storeKeyMaterial(
      id: id,
      purpose: 'group_sender_key',
      wrappedBytes: sealed.encode(),
      wrappingKeyRef: 'keyvault:master',
    );
  }

  Future<(Uint8List, int)?> _loadGroupSenderKey({
    required String groupId,
    required String senderPublicId,
    required int epoch,
  }) async {
    final id = 'grp:${groupId}_ep${epoch}_$senderPublicId';
    final row = await keyMaterialRepo.getKeyMaterial(id);
    if (row == null) return null;
    final wrapKey = await _deriveSessionWrapKey();
    final clear = await SealedEnvelope.open(
      key: wrapKey,
      payload: SealedPayload.decode(
        Uint8List.fromList(row['wrapped_bytes'] as List<int>),
      ),
      aad: utf8.encode(id),
    );
    final map = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return (base64Decode(map['chainKeyB64'] as String), map['msgNo'] as int);
  }

  Future<Uint8List> encryptGroupMessage({
    required String groupId,
    required int epoch,
    required String text,
  }) async {
    final loaded = await _loadGroupSenderKey(
      groupId: groupId,
      senderPublicId: identity.publicId,
      epoch: epoch,
    );
    if (loaded == null) {
      throw StateError('Sender Key inexistente para $groupId época $epoch.');
    }
    final chainKey = loaded.$1;
    final msgNo = loaded.$2;
    final msgKeyMac =
        await _hmacSha256.calculateMac([0x01], secretKey: SecretKey(chainKey));
    final nextChainMac =
        await _hmacSha256.calculateMac([0x02], secretKey: SecretKey(chainKey));

    await _saveGroupSenderKey(
      groupId: groupId,
      senderPublicId: identity.publicId,
      epoch: epoch,
      chainKey: Uint8List.fromList(nextChainMac.bytes),
      messageNo: msgNo + 1,
    );

    final sealed = await SealedEnvelope.seal(
      key: SecretKey(msgKeyMac.bytes),
      plaintext: utf8.encode(text),
      aad: utf8.encode('nix-grp-msg:$groupId:$epoch:$msgNo'),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'groupId': groupId,
      'epoch': epoch,
      'sender': identity.publicId,
      'msgNo': msgNo,
      'sealedB64': base64Encode(sealed.encode()),
    })));
  }

  Future<String> decryptGroupMessage(Uint8List groupEnvelopeBytes) async {
    final map =
        jsonDecode(utf8.decode(groupEnvelopeBytes)) as Map<String, dynamic>;
    final groupId = map['groupId'] as String;
    final epoch = map['epoch'] as int;
    final senderId = map['sender'] as String;
    final targetNo = map['msgNo'] as int;
    final loaded = await _loadGroupSenderKey(
      groupId: groupId,
      senderPublicId: senderId,
      epoch: epoch,
    );
    if (loaded == null) {
      throw StateError(
        'Sem autorização criptográfica (Sender Key ausente para época $epoch).',
      );
    }
    var chainKey = loaded.$1;
    var currentNo = loaded.$2;
    if (targetNo < currentNo) {
      throw StateError('Mensagem de grupo duplicada ou com índice retroativo.');
    }
    while (currentNo < targetNo) {
      final stepNext = await _hmacSha256
          .calculateMac([0x02], secretKey: SecretKey(chainKey));
      chainKey = Uint8List.fromList(stepNext.bytes);
      currentNo++;
    }
    final msgKeyMac =
        await _hmacSha256.calculateMac([0x01], secretKey: SecretKey(chainKey));
    final nextChainMac =
        await _hmacSha256.calculateMac([0x02], secretKey: SecretKey(chainKey));

    final clear = await SealedEnvelope.open(
      key: SecretKey(msgKeyMac.bytes),
      payload: SealedPayload.decode(base64Decode(map['sealedB64'] as String)),
      aad: utf8.encode('nix-grp-msg:$groupId:$epoch:$targetNo'),
    );

    await _saveGroupSenderKey(
      groupId: groupId,
      senderPublicId: senderId,
      epoch: epoch,
      chainKey: Uint8List.fromList(nextChainMac.bytes),
      messageNo: targetNo + 1,
    );
    return utf8.decode(clear);
  }

  static String _toHex(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List _fromHex(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool _constantTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
