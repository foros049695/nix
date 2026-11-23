import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../profile/cultural_cover_art.dart';

class PassportDexSheet extends StatefulWidget {
  final CulturalItem item;
  final VoidCallback? onClose;
  final bool isSidebar;

  const PassportDexSheet({
    super.key,
    required this.item,
    this.onClose,
    this.isSidebar = false,
  });

  static Future<void> showModal(BuildContext context, {required CulturalItem item}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: PassportDexSheet(item: item),
      ),
    );
  }

  @override
  State<PassportDexSheet> createState() => _PassportDexSheetState();
}

class _PassportDexSheetState extends State<PassportDexSheet> {
  late CulturalStage _status;
  late double _rating;

  @override
  void initState() {
    super.initState();
    _status = widget.item.tracking.stage ?? CulturalStage.finished;
    _rating = double.tryParse(widget.item.rating) ?? 9.0;
  }

  void _updateStatus(CulturalStage newStatus, NixState state) {
    setState(() => _status = newStatus);
    final updated = widget.item.copyWith(
      tracking: widget.item.tracking.copyWith(stage: newStatus),
    );
    state.addCulturalItem(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final isBook = widget.item.category == CulturalCategory.books ||
        widget.item.category == CulturalCategory.manga;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF100F1A),
        borderRadius: widget.isSidebar
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(20)),
        border: widget.isSidebar
            ? Border(left: BorderSide(color: NixColors.surfaceBorderStrong))
            : null,
      ),
      child: Column(
        children: [
          // Barra de título com botão fechar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'PASSPORTDEX · FICHA TÉCNICA',
                    style: TextStyle(
                      color: Colors.cyanAccent.shade200,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('close_passport_dex_button'),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Capa da obra em destaque (com modelo 2.5D de livro ou pôster)
                  Center(
                    child: Hero(
                      tag: 'passport_cover_${widget.item.id}',
                      child: CulturalCoverArt(
                        item: widget.item,
                        width: widget.isSidebar ? 140 : 160,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Título principal
                  Text(
                    widget.item.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Criador / Autor e Ano
                  Text(
                    widget.item.creatorOrYear,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NixColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Avaliação e Engajamento
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      Text(
                        _rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '·  133 avaliações',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Botões de Status de Acompanhamento Pessoal
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _statusChip(
                          label: 'concluído',
                          status: CulturalStage.finished,
                          active: _status == CulturalStage.finished,
                          onTap: () => _updateStatus(CulturalStage.finished, state),
                        ),
                        const SizedBox(width: 6),
                        _statusChip(
                          label: isBook ? 'lendo' : 'assistindo',
                          status: CulturalStage.active,
                          active: _status == CulturalStage.active,
                          onTap: () => _updateStatus(CulturalStage.active, state),
                        ),
                        const SizedBox(width: 6),
                        _statusChip(
                          label: 'planejado',
                          status: CulturalStage.planned,
                          active: _status == CulturalStage.planned,
                          onTap: () => _updateStatus(CulturalStage.planned, state),
                        ),
                        const SizedBox(width: 6),
                        _statusChip(
                          label: 'abandonado',
                          status: CulturalStage.dropped,
                          active: _status == CulturalStage.dropped,
                          onTap: () => _updateStatus(CulturalStage.dropped, state),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Sinopse
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sinopse da Obra',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Anne Shirley, uma órfã de onze anos com uma imaginação brilhante e espírito livre, '
                          'é adotada por engano pelos irmãos Marilla e Matthew Cuthbert na fazenda Green Gables.',
                          style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Estatística social do passaporte
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bookmark_added_rounded, size: 16, color: Colors.cyanAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Em 204 passaportes  ·  2 membros lendo agora',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Onde Encontrar / Onde Comprar (Privado)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Onde encontrar',
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _storeButton('Bookshop.org', Icons.auto_stories),
                      const SizedBox(width: 8),
                      _storeButton('Amazon', Icons.shopping_bag_outlined),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required CulturalStage status,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: Key('passport_status_chip_${status.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? Colors.white : Colors.white24,
            width: active ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : NixColors.textMuted,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _storeButton(String name, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
