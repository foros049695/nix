import 'package:flutter/material.dart';

import 'emoji_catalog.dart';

Future<String?> showReactionPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReactionPicker(),
    );

class _ReactionPicker extends StatefulWidget {
  const _ReactionPicker();
  @override
  State<_ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<_ReactionPicker> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final entries = _category == null
        ? {
            ...nixQuickReactions,
            ...nixEmojiCategories.values.expand((entries) => entries)
          }.toList()
        : nixEmojiCategories[_category]!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .53,
      child: Column(children: [
        const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Reagir à mensagem')),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final category in [null, ...nixEmojiCategories.keys])
                Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: ChoiceChip(
                      label: Text(category ?? 'Todos'),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    )),
            ])),
        Expanded(
            child: GridView.builder(
          key: ValueKey(_category),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 52, mainAxisExtent: 48),
          itemCount: entries.length,
          itemBuilder: (context, index) => TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => Navigator.pop(context, entries[index]),
            child: Text(entries[index],
                style: const TextStyle(
                    fontSize: 23, fontFamilyFallback: ['NixEmoji'])),
          ),
        )),
      ]),
    );
  }
}
