import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/publication.dart';
import '../../core/theme/nix_colors.dart';
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
                  color: NixColors.accentPublication.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: NixColors.accentPublication.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'NIX ARCHIVE · OBJETOS CANÔNICOS',
                  style: TextStyle(color: NixColors.accentPublication, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                key: const Key('new_publication_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NixColors.accentPublication,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  _showPublicationEditorDialog(context, nixState);
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
                    return _PublicationCard(
                      publication: pub,
                      onEditRevision: () => _showPublicationEditorDialog(
                        context,
                        nixState,
                        editingTarget: pub,
                      ),
                      onRefute: () => _showRefutationDialog(context, nixState, pub),
                      onInspectHistoryAndIntegrity: () =>
                          _showIntegrityAndHistoryDialog(context, nixState, pub),
                    );
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
          const SizedBox(height: 12),
          Text(
            'Nenhuma publicação arquivada nesta sala.',
            style: TextStyle(color: NixColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Clique em "Nova Publicação" para assinar e salvar um objeto canônico local.',
            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showPublicationEditorDialog(
    BuildContext context,
    NixState nixState, {
    Publication? editingTarget,
  }) {
    final titleCtrl = TextEditingController(text: editingTarget?.title ?? '');
    final bodyCtrl =
        TextEditingController(text: editingTarget?.contentMarkdown ?? '');
    final claimsCtrl = TextEditingController(
      text: editingTarget != null && editingTarget.claims.isNotEmpty
          ? editingTarget.claims.join('\n')
          : 'Afirmação técnica principal verificável',
    );
    String? formError;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: NixColors.surfaceElevatedHigh,
          title: Text(
            editingTarget == null
                ? 'Editor Canônico — Nix Archive'
                : 'Nova Revisão Canônica (supersedes)',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 16),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    editingTarget == null
                        ? 'A publicação será sanitizada contra XSS, assinada com Ed25519 e persistida localmente com CID SHA-256.'
                        : 'Substitui o objeto CID ${editingTarget.cidHash.substring(0, 12)}... preservando o elo histórico imutável.',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('archive_title_input'),
                    controller: titleCtrl,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Título da Publicação / Evidência',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('archive_body_input'),
                    controller: bodyCtrl,
                    maxLines: 5,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Conteúdo Markdown / HTML Sanitizado',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('archive_claims_input'),
                    controller: claimsCtrl,
                    maxLines: 2,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Afirmações Verificáveis (1 por linha)',
                    ),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      formError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
            ),
            ElevatedButton(
              key: const Key('archive_publish_submit_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NixColors.accentPublication,
                foregroundColor: Colors.black,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final title = titleCtrl.text.trim();
                      final body = bodyCtrl.text.trim();
                      if (title.isEmpty || body.isEmpty) {
                        setDlgState(() =>
                            formError = 'Informe o título e o corpo da publicação.');
                        return;
                      }
                      final claimLines = claimsCtrl.text
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      setDlgState(() {
                        busy = true;
                        formError = null;
                      });
                      try {
                        await nixState.publishCanonicalArticle(
                          channelId: channel.id,
                          title: title,
                          rawContent: body,
                          claimTexts: claimLines,
                          supersedesHash: editingTarget?.cidHash,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                editingTarget == null
                                    ? 'Objeto canônico assinado com Ed25519 e salvo no Nix Archive local.'
                                    : 'Nova revisão canônica assinada (supersedes) e salva no Nix Archive.',
                              ),
                              backgroundColor: NixColors.accentPublication,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() {
                          busy = false;
                          formError = 'Falha ao publicar: $e';
                        });
                      }
                    },
              child: Text(
                editingTarget == null ? 'Assinar e Publicar Local' : 'Assinar Revisão',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRefutationDialog(
    BuildContext context,
    NixState nixState,
    Publication target,
  ) {
    final claimIdCtrl = TextEditingController(text: 'c1');
    final rationaleCtrl = TextEditingController();
    String? errorMsg;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: NixColors.surfaceElevatedHigh,
          title: Text(
            'Refutar Publicação Canônica',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 15.5),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alvo: ${target.title} (CID: ${target.cidHash.substring(0, 12)}...)',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('archive_refute_claim_input'),
                  controller: claimIdCtrl,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                  decoration: const InputDecoration(
                    labelText: 'ID da Afirmação Contestada (ex: c1)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('archive_refute_rationale_input'),
                  controller: rationaleCtrl,
                  maxLines: 4,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                  decoration: const InputDecoration(
                    labelText: 'Fundamentação Técnica & Contra-Evidência',
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('archive_refute_submit_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NixColors.accentWarning,
                foregroundColor: Colors.black,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final rationale = rationaleCtrl.text.trim();
                      final claimId = claimIdCtrl.text.trim();
                      if (rationale.isEmpty || claimId.isEmpty) {
                        setDlgState(() => errorMsg = 'Informe o ID da afirmação e a fundamentação.');
                        return;
                      }
                      setDlgState(() {
                        busy = true;
                        errorMsg = null;
                      });
                      try {
                        await nixState.refuteCanonicalArticle(
                          channelId: channel.id,
                          targetCidHash: target.cidHash,
                          targetClaimId: claimId,
                          rationale: rationale,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDlgState(() {
                          busy = false;
                          errorMsg = 'Falha ao refutar: $e';
                        });
                      }
                    },
              child: const Text('Assinar Refutação', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIntegrityAndHistoryDialog(
    BuildContext context,
    NixState nixState,
    Publication pub,
  ) async {
    final verified = await nixState.verifyCanonicalArticleIntegrity(pub.cidHash);
    final history = await nixState.getCanonicalArticleHistory(pub.cidHash);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NixColors.surfaceElevatedHigh,
        title: Row(
          children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.gpp_bad_rounded,
              color: verified ? NixColors.accentGreen : Colors.redAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                verified
                    ? 'Integridade Canônica & Ed25519 Verificadas'
                    : 'Alerta: Falha de Verificação Criptográfica',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 15),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'CID SHA-256: ${pub.cidHash}',
                style: TextStyle(
                  color: NixColors.accentCyan,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                ),
              ),
              if (pub.supersedesHash != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Substitui versão anterior (supersedes): ${pub.supersedesHash}',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Histórico de Revisões (${history.length}):',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              ...history.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${h['hash']} (${h['kind']})',
                      style: TextStyle(
                        color: NixColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )),
              if (pub.refutationSummaries.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Refutações Registradas (${pub.refutationSummaries.length}):',
                  style: TextStyle(
                    color: NixColors.accentWarning,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ...pub.refutationSummaries.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $r',
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                      ),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _PublicationCard extends StatelessWidget {
  final Publication publication;
  final VoidCallback onEditRevision;
  final VoidCallback onRefute;
  final VoidCallback onInspectHistoryAndIntegrity;

  const _PublicationCard({
    required this.publication,
    required this.onEditRevision,
    required this.onRefute,
    required this.onInspectHistoryAndIntegrity,
  });

  @override
  Widget build(BuildContext context) {
    final cidShort = publication.cidHash.length > 10
        ? '${publication.cidHash.substring(0, 10)}...'
        : publication.cidHash;

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
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          publication.isVerifiedSignature
                              ? Icons.verified
                              : Icons.gpp_maybe_outlined,
                          size: 14,
                          color: publication.isVerifiedSignature
                              ? NixColors.accentGreen
                              : NixColors.accentWarning,
                        ),
                        Text(
                          publication.authorPersona,
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          '· ${publication.publishedAt.day}/${publication.publishedAt.month}',
                          style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                        ),
                        if (publication.supersedesHash != null)
                          Text(
                            '· Revisão de ${publication.supersedesHash!.substring(0, 8)}',
                            style: TextStyle(color: NixColors.accentCyan, fontSize: 11),
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
                        'CID: $cidShort',
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
            width: double.infinity,
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
          if (publication.refutationSummaries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NixColors.accentWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: NixColors.accentWarning.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: publication.refutationSummaries
                    .map((r) => Text(
                          'Refutação: $r',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 11.5,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Rodapé com métricas de claims, refutações e ações
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
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
              Wrap(
                spacing: 6,
                children: [
                  TextButton.icon(
                    key: Key('archive_verify_${publication.id}'),
                    onPressed: onInspectHistoryAndIntegrity,
                    icon: const Icon(Icons.verified_user_outlined, size: 14),
                    label: const Text('Verificar / Histórico', style: TextStyle(fontSize: 11.5)),
                  ),
                  TextButton.icon(
                    key: Key('archive_edit_${publication.id}'),
                    onPressed: onEditRevision,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Nova Revisão', style: TextStyle(fontSize: 11.5)),
                  ),
                  TextButton.icon(
                    key: Key('archive_refute_${publication.id}'),
                    onPressed: onRefute,
                    icon: Icon(Icons.gavel_rounded, size: 14, color: NixColors.accentWarning),
                    label: Text(
                      'Refutar',
                      style: TextStyle(fontSize: 11.5, color: NixColors.accentWarning),
                    ),
                  ),
                ],
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
