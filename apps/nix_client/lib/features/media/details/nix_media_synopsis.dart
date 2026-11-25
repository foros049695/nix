import 'package:flutter/material.dart';
import '../../../core/theme/nix_colors.dart';

class NixMediaSynopsis extends StatefulWidget {
  final String synopsis;

  const NixMediaSynopsis({super.key, required this.synopsis});

  @override
  State<NixMediaSynopsis> createState() => _NixMediaSynopsisState();
}

class _NixMediaSynopsisState extends State<NixMediaSynopsis> {
  bool _expanded = false;

  String _cleanText(String raw) {
    var text = raw;
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final clean = _cleanText(widget.synopsis);
    if (clean.isEmpty) return const SizedBox.shrink();

    final isLong = clean.length > 170;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          clean,
          maxLines: _expanded || !isLong ? null : 3,
          overflow: _expanded || !isLong ? TextOverflow.clip : TextOverflow.ellipsis,
          style: TextStyle(
            color: NixColors.textSecondary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                _expanded ? 'recolher' : 'mais',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF64748B),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
