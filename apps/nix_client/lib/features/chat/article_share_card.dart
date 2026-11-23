import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';

class ArticleShareData {
  final String id;
  final String title;
  final String authorName;
  final String authorFingerprint;
  final String publishedAt;
  final String excerpt;
  final bool isVerified;

  const ArticleShareData({
    required this.id,
    required this.title,
    required this.authorName,
    required this.authorFingerprint,
    required this.publishedAt,
    required this.excerpt,
    this.isVerified = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authorName': authorName,
        'authorFingerprint': authorFingerprint,
        'publishedAt': publishedAt,
        'excerpt': excerpt,
        'isVerified': isVerified,
      };

  static ArticleShareData? tryParse(String raw) {
    if (!raw.startsWith('[NIX_ARTICLE]:')) return null;
    try {
      final jsonStr = raw.substring('[NIX_ARTICLE]:'.length).trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ArticleShareData(
        id: map['id'] as String? ?? 'art_${DateTime.now().millisecondsSinceEpoch}',
        title: map['title'] as String? ?? 'Artigo do Arquivo Nix',
        authorName: map['authorName'] as String? ?? 'Autor Soberano',
        authorFingerprint: map['authorFingerprint'] as String? ?? '',
        publishedAt: map['publishedAt'] as String? ?? '2026',
        excerpt: map['excerpt'] as String? ?? '',
        isVerified: map['isVerified'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  String toMessageText() => '[NIX_ARTICLE]:${jsonEncode(toJson())}';
}

class ArticleShareCard extends StatelessWidget {
  final ArticleShareData data;

  const ArticleShareCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: const Color(0xFF16152B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4), width: 1.2),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.auto_stories_rounded, color: Colors.purpleAccent, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NIX ARCHIVE · ARTIGO ASSINADO',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          data.authorName,
                          style: TextStyle(color: NixColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        if (data.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 12, color: Colors.greenAccent),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.title,
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (data.excerpt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              data.excerpt,
              style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5, height: 1.3),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton.icon(
              key: Key('read_article_button_${data.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purpleAccent,
                side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.6)),
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: NixColors.surfaceElevatedHigh,
                    title: Row(
                      children: [
                        const Icon(Icons.auto_stories_rounded, color: Colors.purpleAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(data.title, style: const TextStyle(fontSize: 16))),
                      ],
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Autor: ${data.authorName}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, size: 14, color: Colors.greenAccent),
                              const Text(' Assinatura Ed25519 OK', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(data.excerpt, style: const TextStyle(fontSize: 13, height: 1.5)),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.menu_book_rounded, size: 15),
              label: const Text('Ler Artigo Completo', style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }
}
