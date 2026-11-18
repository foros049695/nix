import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../core/models/publication.dart';
import '../../state/nix_state.dart';

class PublicationRoomView extends StatelessWidget {
  final Channel channel;

  const PublicationRoomView({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final publications = nixState.currentPublications;

    return Column(
      children: [
        // Cabeçalho da Sala de Publicação
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: NixColors.surfaceSidebar,
            border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: NixColors.accentPublication, size: 20),
              const SizedBox(width: 8),
              Text(
                channel.name,
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: NixColors.accentPublication.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.accentPublication.withOpacity(0.3)),
                ),
                child: Text(
                  'NIX ARCHIVE · OBJETOS CANÔNICOS',
                  style: TextStyle(color: NixColors.accentPublication, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NixColors.accentPublication,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  _showNewPublicationDialog(context);
                },
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Nova Publicação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Lista de Artigos Canônicos
        Expanded(
          child: publications.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: publications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final pub = publications[index];
                    return _PublicationCard(publication: pub);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_rounded, size: 48, color: NixColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Nenhuma publicação arquivada nesta sala.',
            style: TextStyle(color: NixColors.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Clique em "Nova Publicação" para assinar e emitir um objeto canônico.',
            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showNewPublicationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editor Canônico — Nix Archive'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toda publicação é assinada pela sua Persona Editorial Ed25519 e recebe um identificador imutável de hash canônico.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(hintText: 'Título da Publicação / Evidência'),
              ),
              SizedBox(height: 12),
              TextField(
                maxLines: 6,
                decoration: InputDecoration(hintText: 'Conteúdo em formato Markdown sanitizado...'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentPublication,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Objeto canônico assinado e propagado nas réplicas opt-in!'),
                  backgroundColor: NixColors.accentPublication,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Assinar e Publicar'),
          ),
        ],
      ),
    );
  }
}

class _PublicationCard extends StatelessWidget {
  final Publication publication;

  const _PublicationCard({required this.publication});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NixColors.surfaceBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título e Assinatura
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      publication.title,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.verified, size: 14, color: NixColors.accentGreen),
                        const SizedBox(width: 4),
                        Text(
                          publication.authorPersona,
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${publication.publishedAt.day}/${publication.publishedAt.month}',
                          style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // CID Tag com cópia
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: publication.cidHash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hash CID copiado para a área de transferência!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCardHover,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fingerprint, size: 14, color: NixColors.accentCyan),
                      const SizedBox(width: 4),
                      Text(
                        'CID: ${publication.cidHash.substring(0, 10)}...',
                        style: const TextStyle(
                          color: NixColors.accentCyan,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Corpo em Markdown
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NixColors.surfaceDock,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              publication.contentMarkdown.trim(),
              style: const TextStyle(
                color: Color(0xFFD1D5DB),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Rodapé com métricas de claims e refutações
          Row(
            children: [
              _buildBadge(
                icon: Icons.checklist_rounded,
                label: '${publication.claimsCount} afirmações verificáveis',
                color: NixColors.accentGreen,
              ),
              const SizedBox(width: 12),
              _buildBadge(
                icon: Icons.compare_arrows_rounded,
                label: '${publication.refutationsCount} refutações registradas',
                color: publication.refutationsCount > 0 ? NixColors.accentWarning : NixColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
