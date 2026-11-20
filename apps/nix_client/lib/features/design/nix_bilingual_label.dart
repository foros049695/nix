import 'package:flutter/material.dart';

class NixBilingualLabel extends StatelessWidget {
  const NixBilingualLabel({
    super.key,
    required this.label,
    required this.japanese,
    this.style,
  });

  final String label;
  final String japanese;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ExcludeSemantics(
          child: Text(
            japanese,
            style: TextStyle(
              color: style?.color,
              fontFamily: 'NixJapanese',
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
