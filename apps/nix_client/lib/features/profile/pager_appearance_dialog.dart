import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/pager_appearance.dart';
import '../../state/nix_state.dart';
import '../design/nix_bilingual_label.dart';
import 'pager_housing.dart';

Future<void> showPagerAppearance(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _PagerAppearanceDialog(),
    );

class _PagerAppearanceDialog extends StatelessWidget {
  const _PagerAppearanceDialog();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final settings = state.settings;
    return AlertDialog(
      scrollable: true,
      title: const NixBilingualLabel(label: 'Cores do Pager', japanese: '配色'),
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 148,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 225),
                  child: ExcludeSemantics(
                    child: PagerHousing(
                      caseColor: settings.pagerCaseColor,
                      lcdColor: settings.pagerLcdColor,
                      reducedMotion: true,
                      minDisplayHeight: 62,
                      screen: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: PagerGuide(
                          message: '> Nix',
                          reducedMotion: true,
                          portraitSize: 38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const NixBilingualLabel(label: 'Carcaça', japanese: '外装'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final color in PagerCaseColor.values)
                  _chip(
                      color.label,
                      color.rgb,
                      settings.pagerCaseColor == color,
                      () => state.updateSettings(
                          settings.copyWith(pagerCaseColor: color))),
              ],
            ),
            const SizedBox(height: 14),
            const NixBilingualLabel(label: 'Visor', japanese: '画面'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final color in PagerLcdColor.values)
                  _chip(
                      color.label,
                      color.rgb,
                      settings.pagerLcdColor == color,
                      () => state.updateSettings(
                          settings.copyWith(pagerLcdColor: color))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Concluir'),
        ),
      ],
    );
  }

  Widget _chip(String label, int rgb, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        avatar: CircleAvatar(backgroundColor: Color(rgb)),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      );
}
