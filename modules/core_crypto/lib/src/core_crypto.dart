import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';

/// Gera uma identidade criptográfica soberana e compartimentalizada para o Project Nix.
///
/// Separa formalmente o par Ed25519 (autenticação e assinatura) do par X25519
/// (troca de chaves Diffie-Hellman), evitando reutilização insegura da mesma chave
/// em algoritmos distintos.
class NixIdentity {
  final SimpleKeyPairData ed25519KeyPair;
  final SimplePublicKey ed25519PublicKey;
  final SimpleKeyPairData x25519KeyPair;
  final SimplePublicKey x25519PublicKey;

  const NixIdentity._({
    required this.ed25519KeyPair,
    required this.ed25519PublicKey,
    required this.x25519KeyPair,
    required this.x25519PublicKey,
  });

  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();

  /// Cria uma nova identidade aleatória utilizando CSPRNG do sistema.
  static Future<NixIdentity> generate() async {
    final edKeyPair = await _ed25519.newKeyPair();
    final xKeyPair = await _x25519.newKeyPair();
    final edExtracted = await edKeyPair.extract();
    final xExtracted = await xKeyPair.extract();
    return NixIdentity._(
      ed25519KeyPair: edExtracted,
      ed25519PublicKey: edExtracted.publicKey,
      x25519KeyPair: xExtracted,
      x25519PublicKey: xExtracted.publicKey,
    );
  }

  /// Restaura uma identidade a partir das sementes de 32 bytes (Ed25519 e X25519).
  static Future<NixIdentity> fromSeeds({
    required List<int> ed25519Seed,
    required List<int> x25519PrivateBytes,
  }) async {
    if (ed25519Seed.length != 32 || x25519PrivateBytes.length != 32) {
      throw ArgumentError('As sementes Ed25519 e X25519 devem ter exatamente 32 bytes.');
    }
    final edPair = await _ed25519.newKeyPairFromSeed(ed25519Seed);
    final xPair = await _x25519.newKeyPairFromSeed(x25519PrivateBytes);
    final edExtracted = await edPair.extract();
    final xExtracted = await xPair.extract();
    return NixIdentity._(
      ed25519KeyPair: edExtracted,
      ed25519PublicKey: edExtracted.publicKey,
      x25519KeyPair: xExtracted,
      x25519PublicKey: xExtracted.publicKey,
    );
  }

  /// Identificador público determinístico derivado por SHA-256 das chaves públicas.
  String get publicId {
    final digest = std_crypto.sha256
        .convert([...ed25519PublicKey.bytes, ...x25519PublicKey.bytes])
        .bytes;
    final hex = _bytesToHex(digest.sublist(0, 8)).toUpperCase();
    return 'NIX-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}';
  }

  /// Pseudônimo anônimo determinístico caso o usuário não defina username opcional.
  String get deterministicHandle {
    final digest = std_crypto.sha256.convert(ed25519PublicKey.bytes).bytes;
    return 'NX-${_bytesToHex(digest.sublist(0, 2)).toUpperCase()}';
  }

  String get ed25519PublicHex => _bytesToHex(ed25519PublicKey.bytes);
  String get x25519PublicHex => _bytesToHex(x25519PublicKey.bytes);

  /// Pacote estritamente público compartilhável no Card ID / handshake.
  NixPublicBundle toPublicBundle() => NixPublicBundle(
        publicId: publicId,
        ed25519PublicKey: ed25519PublicKey,
        x25519PublicKey: x25519PublicKey,
      );

  /// Assina arbitrariamente bytes de payload com Ed25519.
  Future<List<int>> sign(List<int> message) async {
    final sig = await _ed25519.sign(message, keyPair: ed25519KeyPair);
    return sig.bytes;
  }

  /// Verifica assinatura Ed25519 contra uma chave pública informada.
  static Future<bool> verify({
    required List<int> message,
    required List<int> signatureBytes,
    required SimplePublicKey ed25519PublicKey,
  }) {
    return _ed25519.verify(
      message,
      signature: Signature(signatureBytes, publicKey: ed25519PublicKey),
    );
  }
}

/// Representação pública de um par (sem sementes nem material privado).
class NixPublicBundle {
  final String publicId;
  final SimplePublicKey ed25519PublicKey;
  final SimplePublicKey x25519PublicKey;

  const NixPublicBundle({
    required this.publicId,
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
  });
}

/// Payload selado AEAD com XChaCha20-Poly1305 (nonce de 24 bytes + tag MAC de 16 bytes).
class SealedPayload {
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List macBytes;

  const SealedPayload({
    required this.nonce,
    required this.cipherText,
    required this.macBytes,
  });

  /// Codifica em quadro binário compacto `[24B nonce][16B MAC][ciphertext]`.
  Uint8List encode() {
    final out = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(macBytes)
      ..add(cipherText);
    return out.toBytes();
  }

  /// Decodifica quadro binário produzido por [encode].
  factory SealedPayload.decode(List<int> bytes) {
    if (bytes.length < 40) {
      throw const FormatException('Envelope XChaCha20-Poly1305 inválido (< 40 bytes).');
    }
    return SealedPayload(
      nonce: Uint8List.fromList(bytes.sublist(0, 24)),
      macBytes: Uint8List.fromList(bytes.sublist(24, 40)),
      cipherText: Uint8List.fromList(bytes.sublist(40)),
    );
  }
}

/// Cifrador autenticado AEAD utilizando XChaCha20-Poly1305.
class SealedEnvelope {
  static final Xchacha20 _cipher = Xchacha20.poly1305Aead();

  /// Cifra e autentica [plaintext] com suporte opcional a dados associados [aad].
  static Future<SealedPayload> seal({
    required SecretKey key,
    required List<int> plaintext,
    List<int> aad = const [],
  }) async {
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      aad: aad,
    );
    return SealedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      cipherText: Uint8List.fromList(secretBox.cipherText),
      macBytes: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decifra e valida integridade Poly1305; lança [SecretBoxAuthenticationError] em caso de adulteração.
  static Future<Uint8List> open({
    required SecretKey key,
    required SealedPayload payload,
    List<int> aad = const [],
  }) async {
    final box = SecretBox(
      payload.cipherText,
      nonce: payload.nonce,
      mac: Mac(payload.macBytes),
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }
}

/// Derivação de chaves locais a partir de senha utilizando Argon2id.
class PassphraseKdf {
  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int hashLength;

  const PassphraseKdf({
    this.memoryKib = 19456,
    this.iterations = 2,
    this.parallelism = 1,
    this.hashLength = 32,
  });

  /// Perfil reforçado (64 MiB, 3 iterações) para cofres de longa duração.
  const PassphraseKdf.strong()
      : memoryKib = 65536,
        iterations = 3,
        parallelism = 1,
        hashLength = 32;

  /// Gera salt criptográfico aleatório de 16 bytes.
  static Uint8List generateSalt([int length = 16]) {
    final data = SecretKeyData.random(length: length);
    return Uint8List.fromList(data.bytes);
  }

  /// Deriva [SecretKey] via Argon2id a partir de [passphrase] e [salt].
  Future<SecretKeyData> deriveKey({
    required String passphrase,
    required List<int> salt,
  }) async {
    if (salt.length < 8) {
      throw ArgumentError('Salt do Argon2id deve ter pelo menos 8 bytes.');
    }
    final algorithm = Argon2id(
      parallelism: parallelism,
      memory: memoryKib,
      iterations: iterations,
      hashLength: hashLength,
    );
    final derived = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return derived.extract();
  }
}

/// Pré-chave X25519 assinada por Ed25519 para estabelecimento assíncrono X3DH.
class SignedPreKeyBundle {
  final SimplePublicKey identityEd25519;
  final SimplePublicKey identityX25519;
  final SimplePublicKey signedPreKey;
  final List<int> signature;
  final SimplePublicKey? oneTimePreKey;

  const SignedPreKeyBundle({
    required this.identityEd25519,
    required this.identityX25519,
    required this.signedPreKey,
    required this.signature,
    this.oneTimePreKey,
  });

  static Future<SignedPreKeyBundle> create({
    required NixIdentity owner,
    required SimpleKeyPair signedPreKeyPair,
    SimplePublicKey? oneTimePreKey,
  }) async {
    final spkPub = await signedPreKeyPair.extractPublicKey();
    final sig = await owner.sign(spkPub.bytes);
    return SignedPreKeyBundle(
      identityEd25519: owner.ed25519PublicKey,
      identityX25519: owner.x25519PublicKey,
      signedPreKey: spkPub,
      signature: sig,
      oneTimePreKey: oneTimePreKey,
    );
  }

  Future<bool> verifySignature() {
    return NixIdentity.verify(
      message: signedPreKey.bytes,
      signatureBytes: signature,
      ed25519PublicKey: identityEd25519,
    );
  }
}

/// Acordo de chaves assíncrono X3DH (Extended Triple Diffie-Hellman).
class X3dh {
  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _info = utf8.encode('Nix-X3DH-v4-MasterSecret');

  /// Lado iniciador (Alice) calcula segredo mestre com base no bundle de Bob.
  static Future<({SecretKeyData sharedSecret, SimpleKeyPairData ephemeralKeyPair})> initiatorDerive({
    required NixIdentity initiatorIdentity,
    required SignedPreKeyBundle responderBundle,
  }) async {
    final validSpk = await responderBundle.verifySignature();
    if (!validSpk) {
      throw StateError('Assinatura Ed25519 da SignedPreKey do destinatário inválida.');
    }

    final ekPair = await _x25519.newKeyPair();
    final ekExtracted = await ekPair.extract();

    final dh1 = await _x25519.sharedSecretKey(
      keyPair: initiatorIdentity.x25519KeyPair,
      remotePublicKey: responderBundle.signedPreKey,
    );
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: ekExtracted,
      remotePublicKey: responderBundle.identityX25519,
    );
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: ekExtracted,
      remotePublicKey: responderBundle.signedPreKey,
    );

    final ikm = BytesBuilder(copy: false)
      ..add(await dh1.extractBytes())
      ..add(await dh2.extractBytes())
      ..add(await dh3.extractBytes());

    if (responderBundle.oneTimePreKey != null) {
      final dh4 = await _x25519.sharedSecretKey(
        keyPair: ekExtracted,
        remotePublicKey: responderBundle.oneTimePreKey!,
      );
      ikm.add(await dh4.extractBytes());
    }

    final shared = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm.toBytes()),
      nonce: List<int>.filled(32, 0),
      info: _info,
    );
    return (sharedSecret: await shared.extract(), ephemeralKeyPair: ekExtracted);
  }

  /// Lado receptor (Bob) deriva exatamente o mesmo segredo mestre ao receber [initiatorEphemeralPublicKey].
  static Future<SecretKeyData> responderDerive({
    required NixIdentity responderIdentity,
    required SimpleKeyPair responderSignedPreKey,
    required SimplePublicKey initiatorX25519Identity,
    required SimplePublicKey initiatorEphemeralPublicKey,
    SimpleKeyPair? responderOneTimePreKey,
  }) async {
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: responderSignedPreKey,
      remotePublicKey: initiatorX25519Identity,
    );
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: responderIdentity.x25519KeyPair,
      remotePublicKey: initiatorEphemeralPublicKey,
    );
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: responderSignedPreKey,
      remotePublicKey: initiatorEphemeralPublicKey,
    );

    final ikm = BytesBuilder(copy: false)
      ..add(await dh1.extractBytes())
      ..add(await dh2.extractBytes())
      ..add(await dh3.extractBytes());

    if (responderOneTimePreKey != null) {
      final dh4 = await _x25519.sharedSecretKey(
        keyPair: responderOneTimePreKey,
        remotePublicKey: initiatorEphemeralPublicKey,
      );
      ikm.add(await dh4.extractBytes());
    }

    final shared = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm.toBytes()),
      nonce: List<int>.filled(32, 0),
      info: _info,
    );
    return shared.extract();
  }
}

/// Cabeçalho autenticado de uma mensagem no Double Ratchet.
class RatchetHeader {
  final Uint8List dhPublicBytes;
  final int previousChainLength;
  final int messageNumber;

  const RatchetHeader({
    required this.dhPublicBytes,
    required this.previousChainLength,
    required this.messageNumber,
  });

  Uint8List encodeAad() {
    final data = ByteData(8 + dhPublicBytes.length);
    data.setUint32(0, previousChainLength, Endian.big);
    data.setUint32(4, messageNumber, Endian.big);
    final out = data.buffer.asUint8List();
    out.setRange(8, 8 + dhPublicBytes.length, dhPublicBytes);
    return out;
  }

  Map<String, dynamic> toJson() => {
        'dh': _bytesToHex(dhPublicBytes),
        'pn': previousChainLength,
        'n': messageNumber,
      };

  factory RatchetHeader.fromJson(Map<String, dynamic> json) => RatchetHeader(
        dhPublicBytes: _hexToBytes(json['dh'] as String),
        previousChainLength: json['pn'] as int,
        messageNumber: json['n'] as int,
      );
}

/// Mensagem cifrada pelo protocolo Double Ratchet.
class RatchetCiphertext {
  final RatchetHeader header;
  final SealedPayload body;

  const RatchetCiphertext({
    required this.header,
    required this.body,
  });

  /// Serializa a mensagem completa em quadro binário compacto:
  /// `[32B DH Public][4B PrevChainLen][4B MsgNum][24B Nonce][16B MAC][Ciphertext]`.
  Uint8List encode() {
    final headerBytes = ByteData(8);
    headerBytes.setUint32(0, header.previousChainLength, Endian.big);
    headerBytes.setUint32(4, header.messageNumber, Endian.big);
    final builder = BytesBuilder(copy: false)
      ..add(header.dhPublicBytes)
      ..add(headerBytes.buffer.asUint8List())
      ..add(body.encode());
    return builder.toBytes();
  }

  /// Desserializa quadro binário gerado por [encode].
  factory RatchetCiphertext.decode(List<int> bytes) {
    if (bytes.length < 80) {
      throw const FormatException('RatchetCiphertext inválido (< 80 bytes).');
    }
    final dh = Uint8List.fromList(bytes.sublist(0, 32));
    final headerMeta = ByteData.sublistView(Uint8List.fromList(bytes.sublist(32, 40)));
    final pn = headerMeta.getUint32(0, Endian.big);
    final n = headerMeta.getUint32(4, Endian.big);
    final header = RatchetHeader(
      dhPublicBytes: dh,
      previousChainLength: pn,
      messageNumber: n,
    );
    final body = SealedPayload.decode(bytes.sublist(40));
    return RatchetCiphertext(header: header, body: body);
  }
}

/// Implementação do algoritmo Double Ratchet (Signal) com chaves DH X25519,
/// KDF simétrico HKDF-SHA256 / HMAC-SHA256 e cifra AEAD XChaCha20-Poly1305.
class DoubleRatchet {
  static final X25519 _x25519 = X25519();
  static final Hkdf _rootHkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  static final Hmac _hmacSha256 = Hmac.sha256();
  static const int maxSkippedKeys = 256;

  SimpleKeyPairData _dhSelf;
  SimplePublicKey? _dhRemote;
  Uint8List _rootKey;
  Uint8List? _sendChainKey;
  Uint8List? _recvChainKey;
  int _sendMessageNumber = 0;
  int _recvMessageNumber = 0;
  int _previousChainLength = 0;
  final LinkedHashMap<String, Uint8List> _skippedMessageKeys = LinkedHashMap<String, Uint8List>();

  DoubleRatchet._({
    required SimpleKeyPairData dhSelf,
    required SimplePublicKey? dhRemote,
    required Uint8List rootKey,
    Uint8List? sendChainKey,
    Uint8List? recvChainKey,
  })  : _dhSelf = dhSelf,
        _dhRemote = dhRemote,
        _rootKey = rootKey,
        _sendChainKey = sendChainKey,
        _recvChainKey = recvChainKey;

  /// Inicializa a sessão para quem envia a primeira mensagem (Alice).
  static Future<DoubleRatchet> initInitiator({
    required SecretKeyData sharedSecret,
    required SimplePublicKey responderRatchetPublicKey,
  }) async {
    final dhSelf = await (await _x25519.newKeyPair()).extract();
    final dhOut = await _x25519.sharedSecretKey(
      keyPair: dhSelf,
      remotePublicKey: responderRatchetPublicKey,
    );
    final rkAndCk = await _kdfRootKey(
      Uint8List.fromList(sharedSecret.bytes),
      Uint8List.fromList(await dhOut.extractBytes()),
    );
    return DoubleRatchet._(
      dhSelf: dhSelf,
      dhRemote: responderRatchetPublicKey,
      rootKey: rkAndCk.$1,
      sendChainKey: rkAndCk.$2,
      recvChainKey: null,
    );
  }

  /// Inicializa a sessão para o receptor inicial (Bob).
  static Future<DoubleRatchet> initResponder({
    required SecretKeyData sharedSecret,
    required SimpleKeyPair responderRatchetKeyPair,
  }) async {
    return DoubleRatchet._(
      dhSelf: await responderRatchetKeyPair.extract(),
      dhRemote: null,
      rootKey: Uint8List.fromList(sharedSecret.bytes),
      sendChainKey: null,
      recvChainKey: null,
    );
  }

  /// Exporta o estado completo da sessão Double Ratchet para persistência cifrada no SQLCipher.
  Map<String, dynamic> exportState() {
    return {
      'v': 1,
      'dhSelfSeed': _bytesToHex(_dhSelf.bytes),
      'dhRemote': _dhRemote != null ? _bytesToHex(_dhRemote!.bytes) : null,
      'rootKey': _bytesToHex(_rootKey),
      'sendChainKey': _sendChainKey != null ? _bytesToHex(_sendChainKey!) : null,
      'recvChainKey': _recvChainKey != null ? _bytesToHex(_recvChainKey!) : null,
      'sendMessageNumber': _sendMessageNumber,
      'recvMessageNumber': _recvMessageNumber,
      'previousChainLength': _previousChainLength,
      'skipped': {
        for (final entry in _skippedMessageKeys.entries)
          entry.key: _bytesToHex(entry.value),
      },
    };
  }

  /// Restaura uma sessão Double Ratchet a partir do snapshot gerado por [exportState].
  static Future<DoubleRatchet> importState(Map<String, dynamic> state) async {
    if ((state['v'] as int?) != 1) {
      throw FormatException('Versão de estado DoubleRatchet não suportada: ${state['v']}');
    }
    final selfSeed = _hexToBytes(state['dhSelfSeed'] as String);
    final selfPair = await (await _x25519.newKeyPairFromSeed(selfSeed)).extract();
    final remoteHex = state['dhRemote'] as String?;
    final remotePub = remoteHex != null
        ? SimplePublicKey(_hexToBytes(remoteHex), type: KeyPairType.x25519)
        : null;
    final sendHex = state['sendChainKey'] as String?;
    final recvHex = state['recvChainKey'] as String?;

    final dr = DoubleRatchet._(
      dhSelf: selfPair,
      dhRemote: remotePub,
      rootKey: _hexToBytes(state['rootKey'] as String),
      sendChainKey: sendHex != null ? _hexToBytes(sendHex) : null,
      recvChainKey: recvHex != null ? _hexToBytes(recvHex) : null,
    );
    dr._sendMessageNumber = state['sendMessageNumber'] as int? ?? 0;
    dr._recvMessageNumber = state['recvMessageNumber'] as int? ?? 0;
    dr._previousChainLength = state['previousChainLength'] as int? ?? 0;
    final skipped = state['skipped'] as Map?;
    if (skipped != null) {
      for (final entry in skipped.entries) {
        dr._skippedMessageKeys[entry.key.toString()] = _hexToBytes(entry.value.toString());
      }
    }
    return dr;
  }

  SimplePublicKey get currentPublicKey => _dhSelf.publicKey;

  /// Cifra mensagem avançando o Chain Key de envio.
  Future<RatchetCiphertext> encrypt(
    List<int> plaintext, {
    List<int> extraAad = const [],
  }) async {
    if (_sendChainKey == null) {
      throw StateError('Chain key de envio ainda não inicializada.');
    }
    final step = await _kdfChainKey(_sendChainKey!);
    _sendChainKey = step.$1;
    final messageKey = step.$2;

    final header = RatchetHeader(
      dhPublicBytes: Uint8List.fromList(_dhSelf.publicKey.bytes),
      previousChainLength: _previousChainLength,
      messageNumber: _sendMessageNumber,
    );
    _sendMessageNumber += 1;

    final aad = <int>[...header.encodeAad(), ...extraAad];
    final body = await SealedEnvelope.seal(
      key: SecretKey(messageKey),
      plaintext: plaintext,
      aad: aad,
    );
    return RatchetCiphertext(header: header, body: body);
  }

  /// Decifra mensagem tratando entrega fora de ordem e avanço do DH Ratchet
  /// com garantia estrita de execução atômica em estado candidato (Marco P0-1 / CRY01).
  ///
  /// Se a mensagem for forjada ou o AEAD falhar, nenhuma alteração de chave, contador
  /// ou cabeçalho DH é efetivada, preservando a integridade da sessão contra ataques DoS.
  Future<Uint8List> decrypt(
    RatchetCiphertext message, {
    List<int> extraAad = const [],
  }) async {
    final header = message.header;
    final aad = <int>[...header.encodeAad(), ...extraAad];

    // 1. Verifica se é uma mensagem pulada anteriormente armazenada em memória limitada
    final skippedId = _skipMapKey(header.dhPublicBytes, header.messageNumber);
    final skippedMk = _skippedMessageKeys[skippedId];
    if (skippedMk != null) {
      // Abre primeiro; apenas remove a chave pulada se a decifração autenticada passar
      final clear = await SealedEnvelope.open(
        key: SecretKey(skippedMk),
        payload: message.body,
        aad: aad,
      );
      _skippedMessageKeys.remove(skippedId);
      return clear;
    }

    // 2. Snapshot do estado candidato isolado
    var candDhSelf = _dhSelf;
    var candDhRemote = _dhRemote;
    var candRootKey = Uint8List.fromList(_rootKey);
    var candSendChainKey = _sendChainKey != null ? Uint8List.fromList(_sendChainKey!) : null;
    var candRecvChainKey = _recvChainKey != null ? Uint8List.fromList(_recvChainKey!) : null;
    var candSendMessageNumber = _sendMessageNumber;
    var candRecvMessageNumber = _recvMessageNumber;
    var candPreviousChainLength = _previousChainLength;
    final candSkipped = LinkedHashMap<String, Uint8List>.from(_skippedMessageKeys);

    // Se o remetente rotacionou a chave DH, pula mensagens pendentes e avança DH na cópia candidata
    final remoteChanged = candDhRemote == null ||
        !_constantTimeEquals(candDhRemote.bytes, header.dhPublicBytes);

    if (remoteChanged) {
      if (candRecvChainKey != null) {
        if (candRecvMessageNumber + maxSkippedKeys < header.previousChainLength) {
          throw StateError('Salto de mensagens além do limite seguro ($maxSkippedKeys).');
        }
        while (candRecvMessageNumber < header.previousChainLength) {
          final step = await _kdfChainKey(candRecvChainKey!);
          candRecvChainKey = step.$1;
          final keyId = _skipMapKey(candDhRemote!.bytes, candRecvMessageNumber);
          if (candSkipped.length >= maxSkippedKeys) {
            candSkipped.remove(candSkipped.keys.first);
          }
          candSkipped[keyId] = step.$2;
          candRecvMessageNumber += 1;
        }
      }

      candPreviousChainLength = candSendMessageNumber;
      candSendMessageNumber = 0;
      candRecvMessageNumber = 0;
      candDhRemote = SimplePublicKey(header.dhPublicBytes, type: KeyPairType.x25519);

      final dhRecv = await _x25519.sharedSecretKey(
        keyPair: candDhSelf,
        remotePublicKey: candDhRemote,
      );
      final recvStep = await _kdfRootKey(candRootKey, Uint8List.fromList(await dhRecv.extractBytes()));
      candRootKey = recvStep.$1;
      candRecvChainKey = recvStep.$2;

      candDhSelf = await (await _x25519.newKeyPair()).extract();
      final dhSend = await _x25519.sharedSecretKey(
        keyPair: candDhSelf,
        remotePublicKey: candDhRemote,
      );
      final sendStep = await _kdfRootKey(candRootKey, Uint8List.fromList(await dhSend.extractBytes()));
      candRootKey = sendStep.$1;
      candSendChainKey = sendStep.$2;
    }

    // Avança chain de recepção até o índice da mensagem na cópia candidata
    if (candRecvChainKey == null) {
      throw StateError('Chain key de recepção não disponível.');
    }
    if (candRecvMessageNumber + maxSkippedKeys < header.messageNumber) {
      throw StateError('Salto de mensagens além do limite seguro ($maxSkippedKeys).');
    }
    while (candRecvMessageNumber < header.messageNumber) {
      final step = await _kdfChainKey(candRecvChainKey!);
      candRecvChainKey = step.$1;
      final keyId = _skipMapKey(candDhRemote.bytes, candRecvMessageNumber);
      if (candSkipped.length >= maxSkippedKeys) {
        candSkipped.remove(candSkipped.keys.first);
      }
      candSkipped[keyId] = step.$2;
      candRecvMessageNumber += 1;
    }

    final step = await _kdfChainKey(candRecvChainKey!);
    final nextRecvCk = step.$1;
    final messageKey = step.$2;

    // 3. Autenticação AEAD antes do commit: se falhar, SealedEnvelope.open lança exceção e o estado original é preservado
    final clear = await SealedEnvelope.open(
      key: SecretKey(messageKey),
      payload: message.body,
      aad: aad,
    );

    // 4. COMMIT ATÔMICO DO ESTADO: Alcançado apenas após validação de autenticidade
    _dhSelf = candDhSelf;
    _dhRemote = candDhRemote;
    _rootKey = candRootKey;
    _sendChainKey = candSendChainKey;
    _recvChainKey = nextRecvCk;
    _sendMessageNumber = candSendMessageNumber;
    _recvMessageNumber = candRecvMessageNumber + 1;
    _previousChainLength = candPreviousChainLength;
    _skippedMessageKeys.clear();
    _skippedMessageKeys.addAll(candSkipped);

    return clear;
  }

  static Future<(Uint8List, Uint8List)> _kdfRootKey(Uint8List rootKey, Uint8List dhOutput) async {
    final derived = await _rootHkdf.deriveKey(
      secretKey: SecretKey(dhOutput),
      nonce: rootKey,
      info: utf8.encode('Nix-DR-Root'),
    );
    final raw = await derived.extractBytes();
    return (
      Uint8List.fromList(raw.sublist(0, 32)),
      Uint8List.fromList(raw.sublist(32, 64)),
    );
  }

  static Future<(Uint8List, Uint8List)> _kdfChainKey(Uint8List chainKey) async {
    final msgMac = await _hmacSha256.calculateMac([0x01], secretKey: SecretKey(chainKey));
    final nextChainMac = await _hmacSha256.calculateMac([0x02], secretKey: SecretKey(chainKey));
    return (
      Uint8List.fromList(nextChainMac.bytes),
      Uint8List.fromList(msgMac.bytes),
    );
  }

  static String _skipMapKey(List<int> dhBytes, int msgNum) => '${_bytesToHex(dhBytes)}:$msgNum';
}

/// Registro canônico assinado com Ed25519, expiração e proteção contra replay.
class SignedRecord {
  final String recordType;
  final String issuerEd25519Hex;
  final String nonceHex;
  final int issuedAtEpochMs;
  final int expiresAtEpochMs;
  final Map<String, dynamic> payload;
  final String signatureHex;

  const SignedRecord({
    required this.recordType,
    required this.issuerEd25519Hex,
    required this.nonceHex,
    required this.issuedAtEpochMs,
    required this.expiresAtEpochMs,
    required this.payload,
    required this.signatureHex,
  });

  static Future<SignedRecord> create({
    required NixIdentity signer,
    required String recordType,
    required Map<String, dynamic> payload,
    Duration ttl = const Duration(days: 7),
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now().toUtc();
    final expires = timestamp.add(ttl);
    final nonce = _bytesToHex(SecretKeyData.random(length: 16).bytes);
    final canonical = _canonicalBytes(
      recordType: recordType,
      issuerEd25519Hex: signer.ed25519PublicHex,
      nonceHex: nonce,
      issuedAtEpochMs: timestamp.millisecondsSinceEpoch,
      expiresAtEpochMs: expires.millisecondsSinceEpoch,
      payload: payload,
    );
    final sig = await signer.sign(canonical);
    return SignedRecord(
      recordType: recordType,
      issuerEd25519Hex: signer.ed25519PublicHex,
      nonceHex: nonce,
      issuedAtEpochMs: timestamp.millisecondsSinceEpoch,
      expiresAtEpochMs: expires.millisecondsSinceEpoch,
      payload: Map<String, dynamic>.from(payload),
      signatureHex: _bytesToHex(sig),
    );
  }

  /// Verifica assinatura Ed25519, validade temporal e janela de clock-skew.
  Future<bool> verify({
    DateTime? now,
    ReplayGuard? replayGuard,
    Duration maxClockSkew = const Duration(minutes: 5),
  }) async {
    final clock = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    if (clock > expiresAtEpochMs) return false;
    if (issuedAtEpochMs > clock + maxClockSkew.inMilliseconds) return false;

    final canonical = _canonicalBytes(
      recordType: recordType,
      issuerEd25519Hex: issuerEd25519Hex,
      nonceHex: nonceHex,
      issuedAtEpochMs: issuedAtEpochMs,
      expiresAtEpochMs: expiresAtEpochMs,
      payload: payload,
    );

    final pubBytes = _hexToBytes(issuerEd25519Hex);
    final sigBytes = _hexToBytes(signatureHex);
    final sigOk = await NixIdentity.verify(
      message: canonical,
      signatureBytes: sigBytes,
      ed25519PublicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
    );
    if (!sigOk) return false;

    if (replayGuard != null) {
      return replayGuard.accept(
        nonceHex: nonceHex,
        expiresAtEpochMs: expiresAtEpochMs,
        nowEpochMs: clock,
      );
    }
    return true;
  }

  static List<int> _canonicalBytes({
    required String recordType,
    required String issuerEd25519Hex,
    required String nonceHex,
    required int issuedAtEpochMs,
    required int expiresAtEpochMs,
    required Map<String, dynamic> payload,
  }) {
    final canonicalPayload = _canonicalizeValue(payload);
    final body = jsonEncode({
      'domain': 'NIX-RECORD-V4',
      'type': recordType,
      'issuer': issuerEd25519Hex,
      'nonce': nonceHex,
      'iat': issuedAtEpochMs,
      'exp': expiresAtEpochMs,
      'payload': canonicalPayload,
    });
    return utf8.encode(body);
  }

  static dynamic _canonicalizeValue(dynamic val) {
    if (val is Map) {
      final sortedKeys = val.keys.map((k) => k.toString()).toList()..sort();
      return <String, dynamic>{
        for (final k in sortedKeys) k: _canonicalizeValue(val[k]),
      };
    } else if (val is List) {
      return val.map((e) => _canonicalizeValue(e)).toList();
    }
    return val;
  }
}

/// Guarda anti-replay limitada por capacidade e TTL para nonces verificados.
class ReplayGuard {
  final int maxEntries;
  final LinkedHashMap<String, int> _seen = LinkedHashMap<String, int>();

  ReplayGuard({this.maxEntries = 10000});

  bool accept({
    required String nonceHex,
    required int expiresAtEpochMs,
    int? nowEpochMs,
  }) {
    final now = nowEpochMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    _purgeExpired(now);

    if (_seen.containsKey(nonceHex)) {
      return false;
    }
    if (_seen.length >= maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    _seen[nonceHex] = expiresAtEpochMs;
    return true;
  }

  void _purgeExpired(int nowEpochMs) {
    final expired = <String>[];
    for (final entry in _seen.entries) {
      if (entry.value < nowEpochMs) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _seen.remove(key);
    }
  }

  int get trackedCount => _seen.length;
}

String _bytesToHex(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.trim();
  if (clean.length.isOdd) {
    throw FormatException('Hexadecimal inválido (comprimento ímpar): ${clean.length}');
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
