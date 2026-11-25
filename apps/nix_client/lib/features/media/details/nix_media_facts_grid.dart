import 'package:flutter/material.dart';
import '../../../core/theme/nix_colors.dart';

class FactEntry {
  final String label;
  final String value;

  const FactEntry({required this.label, required this.value});
}

class NixMediaFactsGrid extends StatelessWidget {
  final List<FactEntry> facts;

  const NixMediaFactsGrid({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();

    // Divide os fatos em 2 colunas para exibição em grade
    final leftFacts = <FactEntry>[];
    final rightFacts = <FactEntry>[];

    for (var i = 0; i < facts.length; i++) {
      if (i.isEven) {
        leftFacts.add(facts[i]);
      } else {
        rightFacts.add(facts[i]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informações',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: leftFacts.map((f) => _buildFactItem(f)).toList(),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rightFacts.map((f) => _buildFactItem(f)).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFactItem(FactEntry fact) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.label.toLowerCase(),
            style: TextStyle(
              color: NixColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fact.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
