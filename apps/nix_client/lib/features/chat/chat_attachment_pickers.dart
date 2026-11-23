import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/pager_playlist.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import 'article_share_card.dart';

class ArchiveArticlePickerDialog extends StatelessWidget {
  const ArchiveArticlePickerDialog({super.key});

  static Future<ArticleShareData?> show(BuildContext context) {
    return showDialog<ArticleShareData>(
      context: context,
      builder: (_) => const ArchiveArticlePickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final allPubs = state.archiveVm.publications.values.expand((e) => e).toList();

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderModal,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_stories_rounded, color: Colors.purpleAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Compartilhar Artigo do Arquivo',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Artigos são assinados com chaves Ed25519 e verificáveis por qualquer membro.',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: allPubs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.library_books_outlined, size: 42, color: NixColors.textMuted),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhum artigo indexado no momento.',
                              style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: allPubs.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (context, idx) {
                          final pub = allPubs[idx];
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            tileColor: NixColors.surfaceCard,
                            title: Text(
                              pub.title,
                              style: TextStyle(color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              'Por ${pub.authorPersona} · ${pub.publishedAt.year}',
                              style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                            onTap: () {
                              final shareData = ArticleShareData(
                                id: pub.id,
                                title: pub.title,
                                authorName: pub.authorPersona,
                                authorFingerprint: pub.authorFingerprint,
                                publishedAt: pub.publishedAt.toIso8601String().substring(0, 10),
                                excerpt: pub.contentMarkdown.length > 140
                                    ? '${pub.contentMarkdown.substring(0, 140)}...'
                                    : pub.contentMarkdown,
                                isVerified: true,
                              );
                              Navigator.pop(context, shareData);
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMusicPickerDialog extends StatelessWidget {
  const ChatMusicPickerDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ChatMusicPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final playlist = state.pagerPlaylist;

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderModal,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note_rounded, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Compartilhar Música do Acervo',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Selecione uma faixa local da sua playlist do Pager.',
                style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<PagerTrack>>(
                  future: playlist?.load() ?? Future.value([]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tracks = snapshot.data ?? [];
                    if (tracks.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.audiotrack_outlined, size: 42, color: NixColors.textMuted),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhuma faixa vinculada na playlist local.',
                              style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (context, idx) {
                        final track = tracks[idx];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          tileColor: NixColors.surfaceCard,
                          leading: const CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black26,
                            child: Icon(Icons.audiotrack_rounded, size: 16, color: Colors.cyanAccent),
                          ),
                          title: Text(
                            track.name,
                            style: TextStyle(color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: const Text('Arquivo local (.wav)', style: TextStyle(color: Colors.green, fontSize: 11)),
                          trailing: const Icon(Icons.send_rounded, size: 16),
                          onTap: () => Navigator.pop(context, track.name),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
