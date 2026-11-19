import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

/// Gerenciador determinístico da Seed A (mensageria) com verificação de integridade.
///
/// Utiliza lista canônica de 256 palavras únicas:
/// - 23 bytes (184 bits) de entropia CSPRNG + 1 byte de checksum SHA-256 = 24 palavras.
/// - Derivação estritamente isolada por domínio (`Nix-SeedA-Ed25519-v1` e
///   `Nix-SeedA-X25519-v1`), completamente separada de qualquer carteira Monero
///   (`Seed B` — ADR-0003).
class SeedRecoveryManager {
  /// Exatamente 256 palavras únicas para codificação 1:1 sem ambiguidade de byte + checksum.
  static const List<String> wordlist = [
    'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract',
    'absurd', 'abuse', 'access', 'accident', 'account', 'accuse', 'achieve', 'acid',
    'acoustic', 'acquire', 'across', 'act', 'action', 'actor', 'actress', 'actual',
    'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance',
    'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
    'agree', 'ahead', 'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
    'alcohol', 'alert', 'alien', 'all', 'alley', 'allow', 'almost', 'alone',
    'alpha', 'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among',
    'amount', 'amused', 'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry',
    'animal', 'ankle', 'announce', 'annual', 'another', 'answer', 'antenna', 'antique',
    'anxiety', 'any', 'apart', 'apology', 'appear', 'apple', 'approve', 'april',
    'arch', 'arctic', 'area', 'arena', 'argue', 'arm', 'armed', 'armor',
    'army', 'around', 'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artefact',
    'artist', 'artwork', 'ask', 'aspect', 'assault', 'asset', 'assist', 'assume',
    'asthma', 'athlete', 'atom', 'attack', 'attend', 'attitude', 'attract', 'auction',
    'audit', 'august', 'aunt', 'author', 'auto', 'autumn', 'average', 'avocado',
    'avoid', 'awake', 'aware', 'away', 'awesome', 'awful', 'awkward', 'axis',
    'baby', 'bachelor', 'bacon', 'badge', 'bag', 'balance', 'balcony', 'ball',
    'bamboo', 'banana', 'banner', 'bar', 'barely', 'bargain', 'barrel', 'base',
    'basic', 'basket', 'battle', 'beach', 'bean', 'beauty', 'because', 'become',
    'beef', 'before', 'begin', 'behave', 'behind', 'believe', 'below', 'belt',
    'bench', 'benefit', 'best', 'betray', 'better', 'between', 'beyond', 'bicycle',
    'bid', 'bike', 'bind', 'biology', 'bird', 'birth', 'bitter', 'black',
    'blade', 'blame', 'blanket', 'blast', 'bleak', 'bless', 'blind', 'blood',
    'blossom', 'blouse', 'blue', 'blur', 'blush', 'board', 'boat', 'body',
    'boil', 'bomb', 'bone', 'bonus', 'book', 'boost', 'border', 'boring',
    'borrow', 'boss', 'bottom', 'bounce', 'box', 'boy', 'bracket', 'brain',
    'brand', 'brass', 'brave', 'bread', 'breeze', 'brick', 'bridge', 'brief',
    'bright', 'bring', 'brisk', 'broccoli', 'broken', 'bronze', 'broom', 'brother',
    'brown', 'brush', 'bubble', 'buddy', 'budget', 'buffalo', 'build', 'bulb',
    'bulk', 'bullet', 'bundle', 'bunker', 'burden', 'burger', 'burst', 'bus',
    'business', 'busy', 'butter', 'buyer', 'buzz', 'cabbage', 'cabin', 'cable',
  ];

  static final Map<String, int> _wordIndex = {
    for (int i = 0; i < wordlist.length; i++) wordlist[i]: i,
  };

  /// Gera frase mnemônica criptográfica de 24 palavras (23 bytes entropia + 1 byte checksum SHA-256).
  static List<String> generateMnemonic() {
    assert(wordlist.length == 256 && _wordIndex.length == 256);
    final entropySecret = SecretKeyData.random(length: 23);
    final entropy = Uint8List.fromList(entropySecret.bytes);
    try {
      final checksumByte = std_crypto.sha256.convert(entropy).bytes[0];
      return [
        for (final b in entropy) wordlist[b],
        wordlist[checksumByte],
      ];
    } finally {
      entropy.fillRange(0, entropy.length, 0);
    }
  }

  /// Valida formato, vocabulário e checksum SHA-256 da frase mnemônica de 24 palavras.
  static bool validateMnemonic(List<String> words) {
    if (words.length != 24) return false;
    final decoded = Uint8List(24);
    try {
      for (int i = 0; i < 24; i++) {
        final idx = _wordIndex[words[i].trim().toLowerCase()];
        if (idx == null) return false;
        decoded[i] = idx;
      }
      final expectedChecksum =
          std_crypto.sha256.convert(decoded.sublist(0, 23)).bytes[0];
      return decoded[23] == expectedChecksum;
    } finally {
      decoded.fillRange(0, decoded.length, 0);
    }
  }

  /// Deriva de forma determinística a [NixIdentity] completa (Ed25519 + X25519 + Public ID)
  /// a partir da Seed A de 24 palavras. Lança [FormatException] se inválida.
  static Future<NixIdentity> deriveIdentityFromMnemonic(
      List<String> words) async {
    if (!validateMnemonic(words)) {
      throw const FormatException(
        'Frase mnemônica Seed A inválida ou com falha de checksum.',
      );
    }

    final normalized = words.map((w) => w.trim().toLowerCase()).join(' ');
    final ikmBytes = Uint8List.fromList(utf8.encode(normalized));
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    Uint8List? edSeed;
    Uint8List? xSeed;
    try {
      final edKey = await hkdf.deriveKey(
        secretKey: SecretKey(ikmBytes),
        nonce: utf8.encode('nix-seed-a-salt-v1'),
        info: utf8.encode('Nix-SeedA-Ed25519-v1'),
      );
      final xKey = await hkdf.deriveKey(
        secretKey: SecretKey(ikmBytes),
        nonce: utf8.encode('nix-seed-a-salt-v1'),
        info: utf8.encode('Nix-SeedA-X25519-v1'),
      );
      edSeed = Uint8List.fromList(await edKey.extractBytes());
      xSeed = Uint8List.fromList(await xKey.extractBytes());
      return await NixIdentity.fromSeeds(
        ed25519Seed: edSeed,
        x25519PrivateBytes: xSeed,
      );
    } finally {
      ikmBytes.fillRange(0, ikmBytes.length, 0);
      edSeed?.fillRange(0, edSeed.length, 0);
      xSeed?.fillRange(0, xSeed.length, 0);
    }
  }
}
