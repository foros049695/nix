import 'package:flutter/material.dart';

const _icons = <(String, String, IconData)>[
  ('i:shield', 'Escudo', Icons.shield_outlined),
  ('i:radio', 'Rádio', Icons.settings_input_antenna),
  ('i:lock', 'Cadeado', Icons.lock_outline),
  ('i:bolt', 'Raio', Icons.bolt),
  ('i:globe', 'Globo', Icons.public),
  ('i:tag', 'Etiqueta', Icons.sell_outlined),
  ('i:chat', 'Conversa', Icons.chat_bubble_outline),
  ('i:book', 'Livro', Icons.menu_book_outlined),
  ('i:music', 'Música', Icons.music_note_outlined),
  ('i:art', 'Arte', Icons.palette_outlined),
  ('i:code', 'Código', Icons.code),
  ('i:game', 'Jogo', Icons.sports_esports_outlined),
  ('i:film', 'Filme', Icons.movie_outlined),
  ('i:stars', 'Estrela', Icons.star_outline),
  ('i:work', 'Trabalho', Icons.work_outline),
];

const _emojis = <(String, String)>[
  ('🛡️', 'Escudo'),
  ('📡', 'Antena'),
  ('🔒', 'Cadeado'),
  ('⚡', 'Raio'),
  ('🌐', 'Globo'),
  ('🦊', 'Raposa'),
  ('🦉', 'Coruja'),
  ('🎮', 'Controle de jogo'),
  ('🎵', 'Nota musical'),
  ('🎧', 'Fones'),
  ('🎬', 'Cinema'),
  ('📚', 'Livros'),
  ('💻', 'Computador'),
  ('🌙', 'Lua'),
  ('⭐', 'Estrela'),
  ('🔥', 'Fogo'),
  ('🚀', 'Foguete'),
  ('🎨', 'Paleta'),
  ('🧭', 'Bússola'),
  ('📌', 'Marcador'),
  ('💡', 'Ideia'),
  ('✅', 'Concluído'),
  ('🎉', 'Festa'),
  ('😊', 'Sorriso'),
  ('😂', 'Rindo'),
  ('😍', 'Adorei'),
  ('👍', 'Positivo'),
  ('👋', 'Olá'),
  ('🤔', 'Pensando'),
  ('😎', 'Óculos'),
  ('👀', 'Olhos'),
  ('✨', 'Brilho'),
  ('💜', 'Coração roxo'),
  ('👾', 'Alien'),
  ('☕', 'Café'),
  ('🎯', 'Alvo'),
  ('💬', 'Balão de chat'),
  ('📷', 'Câmera'),
  ('📦', 'Caixa'),
  ('🗺️', 'Mapa'),
];

class NixSymbol extends StatelessWidget {
  final String value;
  final double size;
  final Color? color;

  const NixSymbol(this.value, {super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    for (final (id, _, icon) in _icons) {
      if (value == id) return Icon(icon, color: color, size: size);
    }
    if (value.startsWith('i:')) {
      return Icon(Icons.sell_outlined, color: color, size: size);
    }
    return Text(
      value,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFamilyFallback: const ['NixEmoji'],
      ),
    );
  }
}

Future<String?> showNixSymbolPicker(BuildContext context, String selected) {
  return showDialog<String>(
    context: context,
    builder: (context) => DefaultTabController(
      initialIndex: selected.isNotEmpty && !selected.startsWith('i:') ? 1 : 0,
      length: 2,
      child: AlertDialog(
        title: const Text('Escolher ícone ou emoji'),
        content: SizedBox(
          width: 390,
          height: MediaQuery.sizeOf(context).height < 650 ? 216 : 292,
          child: Column(
            children: [
              const TabBar(tabs: [Tab(text: 'Ícones'), Tab(text: 'Emojis')]),
              Expanded(
                child: TabBarView(
                  children: [
                    _SymbolGrid([
                      for (final (id, label, _) in _icons) (id, label),
                    ], selected),
                    _SymbolGrid(_emojis, selected),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );
}

class _SymbolGrid extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;

  const _SymbolGrid(this.options, this.selected);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.extent(
      maxCrossAxisExtent: 62,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: const EdgeInsets.only(top: 8),
      children: [
        for (final (value, label) in options)
          IconButton(
            tooltip: label,
            isSelected: selected == value,
            style: selected == value
                ? IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  )
                : null,
            onPressed: () => Navigator.pop(context, value),
            icon: NixSymbol(value, size: 23),
          ),
      ],
    );
  }
}
