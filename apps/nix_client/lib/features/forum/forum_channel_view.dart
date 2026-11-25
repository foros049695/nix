import '../../core/archive/archive_image.dart';
import '../archive/archive_image_picker.dart';
import '../chat/chat_inline_format.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/forum_post.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../navigation/interface_wallpaper_layer.dart';
import '../chat/message_header.dart';
import '../dialogs/nix_symbol_picker.dart';

/// Visualização de Canal de Tópicos / Fórum Interativo (Inspirado nas Imagens 9 e 10).
/// Exibe grade de cartões com fotos 2x2 e abre um Split-Chat interativo lateral ao selecionar um tópico.
class ForumChannelView extends StatefulWidget {
  final Channel channel;

  const ForumChannelView({super.key, required this.channel});

  static void showCreateTopicModal(
    BuildContext context,
    NixState state,
    Channel channel, {
    String? initialTitle,
  }) =>
      _ForumChannelViewState.showCreateTopicModal(
        context,
        state,
        channel,
        initialTitle: initialTitle,
      );

  @override
  State<ForumChannelView> createState() => _ForumChannelViewState();
}

class _ForumChannelViewState extends State<ForumChannelView> {
  String _searchQuery = '';
  String _selectedTag = 'Todos';
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateTopicModal({String? initialTitle}) {
    ForumChannelView.showCreateTopicModal(
      context,
      context.read<NixState>(),
      widget.channel,
      initialTitle: initialTitle,
    );
  }

  void _submitComment(NixState state, String postId) {
    final text = _commentController.text;
    if (text.trim().isEmpty) return;
    if (state.addForumComment(postId, text)) {
      _commentController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este fórum não aceita seu comentário agora.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final allPosts = nixState.currentForumPosts;
    final tags = nixState.forumTagsFor(widget.channel.id);
    final availableTags = ['Todos', ...tags.keys];
    final selectedPost = nixState.selectedForumPost;
    final selectedTag = availableTags.contains(_selectedTag) ? _selectedTag : 'Todos';

    final filteredPosts = allPosts.where((post) {
      final matchesTag = selectedTag == 'Todos' || post.tags.contains(selectedTag);
      final matchesSearch = _searchQuery.trim().isEmpty ||
          post.title.toLowerCase().contains(_searchQuery.trim().toLowerCase()) ||
          post.description.toLowerCase().contains(_searchQuery.trim().toLowerCase());
      return matchesTag && matchesSearch;
    }).toList();

    return Column(
      children: [
        MessageHeader(channel: widget.channel),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSplitThread = selectedPost != null && constraints.maxWidth >= 720;

              return Row(
                children: [
                  // Coluna Esquerda / Principal: Busca, Tags e Grade de Cartões com Imagens
                  Expanded(
                    flex: showSplitThread ? 6 : 10,
                    child: Container(
                      color: InterfaceWallpaperLayer.translucentPanelsOf(context)
                          ? Colors.transparent
                          : NixColors.background,
                      child: Column(
                        children: [
                          // Barra de Busca + Botão Novo Tópico
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (v) => setState(() => _searchQuery = v),
                                    onSubmitted: (v) {
                                      if (v.trim().isNotEmpty) {
                                        _openCreateTopicModal(initialTitle: v.trim());
                                      }
                                    },
                                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13.5),
                                    decoration: InputDecoration(
                                      hintText: 'Pesquisar ou criar um tópico...',
                                      prefixIcon:
                                          Icon(Icons.search_rounded, color: NixColors.textMuted),
                                      suffixIcon: _searchQuery.trim().isNotEmpty
                                          ? TextButton.icon(
                                              onPressed: () => _openCreateTopicModal(
                                                initialTitle: _searchQuery.trim(),
                                              ),
                                              icon: Icon(Icons.add_rounded,
                                                  size: 16, color: context.accentColor),
                                              label: Text(
                                                'Criar',
                                                style: TextStyle(
                                                  color: context.accentColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : null,
                                      fillColor: NixColors.surfaceCard,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  key: const Key('forum_btn_novo_topico'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.accentColor,
                                    foregroundColor: context.onAccentColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: NixTokens.borderSm),
                                  ),
                                  onPressed: () => _openCreateTopicModal(
                                    initialTitle: _searchQuery.trim().isNotEmpty
                                        ? _searchQuery.trim()
                                        : null,
                                  ),
                                  icon: const Icon(Icons.add_comment_rounded, size: 16),
                                  label: const Text(
                                    'Novo Tópico',
                                    style: TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (nixState.canManageForumTags)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _showTagDialog(context, nixState),
                                icon: const Icon(Icons.sell_outlined),
                                label: const Text('Criar tag'),
                              ),
                            ),

                          // Barra de Tags / Filtros
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              itemCount: availableTags.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (context, idx) {
                                final tag = availableTags[idx];
                                final isSelected = selectedTag == tag;
                                final labelColor = isSelected
                                    ? context.onAccentColor : NixColors.textSecondary;
                                return InkWell(
                                  onTap: () => setState(() => _selectedTag = tag),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? context.accentColor : NixColors.surfaceCard,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? context.accentColor : NixColors.surfaceBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (tags[tag] case final symbol?) ...[
                                          NixSymbol(symbol, size: 15, color: labelColor),
                                          const SizedBox(width: 5),
                                        ],
                                        Text(tag, style: TextStyle(color: labelColor, fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Grade de Cartões de Tópicos (Estilo Imagens 9 e 10) ou Estado Vazio Amigável
                          Expanded(
                            child: filteredPosts.isEmpty
                                ? Center(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 36),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 64,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: context.accentColor
                                                  .withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: context.accentColor
                                                    .withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Icon(Icons.forum_outlined,
                                                size: 30,
                                                color: context.accentColor),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _searchQuery.isNotEmpty ||
                                                    selectedTag != 'Todos'
                                                ? 'Nenhum tópico encontrado'
                                                : 'Nenhum tópico criado ainda neste espaço',
                                            style: TextStyle(
                                              color: NixColors.textPrimary,
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 440),
                                            child: Text(
                                              _searchQuery.isNotEmpty ||
                                                      selectedTag != 'Todos'
                                                  ? 'Não encontramos tópicos para "$_searchQuery". Deseja criá-lo agora?'
                                                  : 'Você ativou os tópicos neste canal! Crie tópicos para organizar discussões, fotos e análises de forma estruturada.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: NixColors.textMuted,
                                                  fontSize: 12.5),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          ElevatedButton.icon(
                                            key: const Key(
                                                'forum_btn_empty_create_topic'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  context.accentColor,
                                              foregroundColor:
                                                  context.onAccentColor,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 22,
                                                      vertical: 13),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      NixTokens.borderSm),
                                            ),
                                            onPressed: () =>
                                                _openCreateTopicModal(
                                              initialTitle: _searchQuery
                                                      .trim()
                                                      .isNotEmpty
                                                  ? _searchQuery.trim()
                                                  : null,
                                            ),
                                            icon: const Icon(
                                                Icons.add_comment_rounded,
                                                size: 18),
                                            label: Text(
                                              _searchQuery.trim().isNotEmpty
                                                  ? 'Criar tópico "${_searchQuery.trim()}"'
                                                  : 'Criar Primeiro Tópico',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, gridConstraints) {
                                      final cols = gridConstraints.maxWidth > 760
                                          ? 3
                                          : (gridConstraints.maxWidth > 460
                                              ? 2
                                              : 1);
                                      return GridView.builder(
                                        padding: const EdgeInsets.all(18),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          crossAxisSpacing: 14,
                                          mainAxisSpacing: 14,
                                          mainAxisExtent: 310,
                                        ),
                                        itemCount: filteredPosts.length,
                                        itemBuilder: (context, idx) {
                                          final post = filteredPosts[idx];
                                          final isSelected =
                                              selectedPost?.id == post.id;
                                          final canEdit =
                                              nixState.canEditForumPost(post);
                                          return _ForumPostCard(
                                            post: post,
                                            isSelected: isSelected,
                                            onTap: () => nixState
                                                .selectForumPost(post),
                                            onEdit: canEdit
                                                ? () => _showEditTopicModal(
                                                    context, nixState, post)
                                                : null,
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Coluna Direita: Split-View Interactive Thread Chat (Imagem 10)
                  if (showSplitThread)
                    Expanded(
                      flex: 5,
                      child: _SplitThreadPanel(
                        post: selectedPost,
                        commentController: _commentController,
                        onSendComment: () => _submitComment(nixState, selectedPost.id),
                        onClose: () => nixState.selectForumPost(null),
                        canEdit: nixState.canEditForumPost(selectedPost),
                        onEdit: () => _showEditTopicModal(context, nixState, selectedPost),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTagDialog(BuildContext context, NixState state) {
    var name = '';
    var icon = 'i:tag';
    String? error;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        scrollable: true,
        title: const Text('Criar tag deste canal'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            maxLength: 32,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(labelText: 'Nome da tag'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final value = await showNixSymbolPicker(ctx, icon);
              if (ctx.mounted && value != null) update(() => icon = value);
            },
            icon: NixSymbol(icon),
            label: const Text('Escolher ícone ou emoji'),
          ),
          if (error != null) Text(error!),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (state.createForumTag(name, icon)) {
                Navigator.pop(ctx);
              } else {
                update(() => error = 'Tag inválida ou já existente neste canal.');
              }
            },
            child: const Text('Criar tag'),
          ),
        ],
      )),
    );
  }

  static void showCreateTopicModal(
    BuildContext context,
    NixState state,
    Channel channel, {
    String? initialTitle,
  }) {
    var title = initialTitle ?? '';
    final titleController = TextEditingController(text: title);
    var description = '';
    String? chosenTag;
    final images = <ArchiveImage>[];
    var picking = false;
    final tags = state.forumTagsFor(channel.id);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Criar Novo Tópico no Fórum'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tags.isNotEmpty)
                  Text('TAG OPCIONAL', style: NixTokens.labelUppercase()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: tags.keys.map((t) {
                    final selected = chosenTag == t;
                    return ChoiceChip(
                      avatar: NixSymbol(tags[t]!, size: 15, color: selected ? ctx.onAccentColor : NixColors.textPrimary),
                      label: Text(t, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: ctx.accentColor,
                      labelStyle: TextStyle(
                        color: selected ? ctx.onAccentColor : NixColors.textPrimary,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (value) => setModalState(() => chosenTag = value ? t : null),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text('TÍTULO DO TÓPICO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  onChanged: (value) => title = value,
                  maxLength: 120,
                  decoration: const InputDecoration(hintText: 'ex: Análise de Antena 915MHz...'),
                ),
                const SizedBox(height: 12),
                Text('DESCRIÇÃO / ESPECIFICAÇÕES', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (value) => description = value,
                  contextMenuBuilder: buildChatFormatMenu,
                  maxLength: 8000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Inclua peso, dimensões, hash ou observações...',
                  ),
                ),
                for (final (index, image) in images.indexed)
                  ListTile(
                    leading: Image.memory(image.bytes, width: 58, height: 42, fit: BoxFit.contain),
                    title: Text('Imagem ${index + 1}'),
                    trailing: IconButton(
                      tooltip: 'Remover imagem',
                      onPressed: picking ? null : () => setModalState(() => images.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: picking || images.length >= ArchiveImage.maxImages ? null : () async {
                    setModalState(() => picking = true);
                    try {
                      final image = await ArchiveImagePicker.pick(ctx);
                      if (image != null && ctx.mounted) {
                        ArchiveImage.validateLimits([...images, image]);
                        setModalState(() => images.add(image));
                      }
                    } catch (_) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Imagem inválida ou limite de tamanho excedido.')),
                      );
                    } finally {
                      if (ctx.mounted) setModalState(() => picking = false);
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Adicionar imagem'),
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
                backgroundColor: ctx.accentColor,
                foregroundColor: ctx.onAccentColor,
              ),
              onPressed: picking ? null : () {
                if (title.trim().isNotEmpty) {
                  final created = state.createForumPost(
                    channelId: channel.id,
                    title: title,
                    description: description,
                    tags: [if (chosenTag != null) chosenTag!],
                    images: images,
                  );
                  if (created) {
                    Navigator.pop(ctx);
                  } else {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Este fórum não aceita novos tópicos agora.')),
                    );
                  }
                }
              },
              child: const Text('Publicar Tópico', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTopicModal(BuildContext context, NixState state, ForumPost post) {
    final titleController = TextEditingController(text: post.title);
    final descController = TextEditingController(text: post.description);
    String? chosenTag = post.tags.isNotEmpty ? post.tags.first : null;
    final images = post.images.map((spec) => spec.image).whereType<ArchiveImage>().toList();
    var picking = false;
    final tags = state.forumTagsFor(widget.channel.id);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Editar Tópico'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tags.isNotEmpty)
                  Text('TAG OPÇÃO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: tags.keys.map((t) {
                    final selected = chosenTag == t;
                    return ChoiceChip(
                      avatar: NixSymbol(tags[t]!, size: 15, color: selected ? ctx.onAccentColor : NixColors.textPrimary),
                      label: Text(t, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: ctx.accentColor,
                      labelStyle: TextStyle(
                        color: selected ? ctx.onAccentColor : NixColors.textPrimary,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (value) => setModalState(() => chosenTag = value ? t : null),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text('TÍTULO DO TÓPICO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  maxLength: 120,
                  decoration: const InputDecoration(hintText: 'ex: Análise de Antena 915MHz...'),
                ),
                const SizedBox(height: 12),
                Text('DESCRIÇÃO / ESPECIFICAÇÕES', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  contextMenuBuilder: buildChatFormatMenu,
                  maxLength: 8000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Inclua peso, dimensões, hash ou observações...',
                  ),
                ),
                for (final (index, image) in images.indexed)
                  ListTile(
                    leading: Image.memory(image.bytes, width: 58, height: 42, fit: BoxFit.contain),
                    title: Text('Imagem ${index + 1}'),
                    trailing: IconButton(
                      tooltip: 'Remover imagem',
                      onPressed: picking ? null : () => setModalState(() => images.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: picking || images.length >= ArchiveImage.maxImages ? null : () async {
                    setModalState(() => picking = true);
                    try {
                      final image = await ArchiveImagePicker.pick(ctx);
                      if (image != null && ctx.mounted) {
                        ArchiveImage.validateLimits([...images, image]);
                        setModalState(() => images.add(image));
                      }
                    } catch (_) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Imagem inválida ou limite de tamanho excedido.')),
                      );
                    } finally {
                      if (ctx.mounted) setModalState(() => picking = false);
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Adicionar imagem'),
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
                backgroundColor: ctx.accentColor,
                foregroundColor: ctx.onAccentColor,
              ),
              onPressed: picking ? null : () {
                final newTitle = titleController.text.trim();
                if (newTitle.isNotEmpty) {
                  try {
                    final updated = state.editForumPost(
                      postId: post.id,
                      title: newTitle,
                      description: descController.text,
                      tags: [if (chosenTag != null) chosenTag!],
                      images: images,
                    );
                    if (updated) {
                      Navigator.pop(ctx);
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Não foi possível salvar as alterações.')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Salvar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForumPostCard extends StatelessWidget {
  final ForumPost post;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _ForumPostCard({
    required this.post,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: NixTokens.borderMd,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.surfaceCardHover : NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(
            color: isSelected ? context.accentColor : NixColors.surfaceBorderStrong,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Autor + Badge NEW + Edit button
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${post.authorName} · há ${DateTime.now().difference(post.createdAt).inHours.clamp(1, 24)}h${post.editedAt != null ? ' · (editado)' : ''}',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: Icon(Icons.edit_outlined, size: 14, color: NixColors.textMuted),
                    tooltip: 'Editar tópico',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onEdit,
                  ),
                if (onEdit != null) const SizedBox(width: 4),
                if (post.isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NixColors.textPrimary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            // Grade 2x2 de Imagens de Inspeção (Estilo Imagens 9 e 10)
            Expanded(
              child: ClipRRect(
                borderRadius: NixTokens.borderSm,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: post.images.take(4).length,
                  itemBuilder: (context, i) {
                    final img = post.images[i];
                    final photo = img.image;
                    if (photo != null) return Image.memory(photo.bytes, fit: BoxFit.contain);
                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1F2024), Color(0xFF0E0F11)],
                        ),
                        border: Border.all(color: NixColors.surfaceActive, width: 0.5),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              Icons.photo_camera_back_outlined,
                              size: 22,
                              color: NixColors.textPrimary.withOpacity(0.25),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 4,
                            child: Text(
                              img.code,
                              style: TextStyle(
                                color: NixColors.textMuted,
                                fontSize: 8.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            left: 4,
                            right: 4,
                            child: Text(
                              img.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: NixColors.textSecondary,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Rodapé do Card: Tags + Contador de Comentários + Selo Verificado
            Row(
              children: [
                if (post.tags.isNotEmpty)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: NixColors.surfaceActive,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _ForumTagLabel(
                          channelId: post.channelId, label: post.tags.first,
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 6),
                Icon(Icons.mode_comment_outlined, size: 12, color: NixColors.textMuted),
                const SizedBox(width: 3),
                Text(
                  '${post.comments.length}',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: NixColors.surfaceBorderStrong),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'OK',
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Painel Lateral de Conversa Interativa do Tópico (Split-View — Estilo Imagem 10).
class _SplitThreadPanel extends StatelessWidget {
  final ForumPost post;
  final TextEditingController commentController;
  final VoidCallback onSendComment;
  final VoidCallback onClose;
  final bool canEdit;
  final VoidCallback? onEdit;

  const _SplitThreadPanel({
    required this.post,
    required this.commentController,
    required this.onSendComment,
    required this.onClose,
    this.canEdit = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InterfaceWallpaperLayer.translucentPanelsOf(context)
            ? NixColors.surfaceSidebar.withValues(
                alpha: InterfaceWallpaperLayer.panelOpacityOf(context))
            : NixColors.surfaceSidebar,
        border: Border(left: BorderSide(color: NixColors.surfaceBorderStrong, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topo do Painel Lateral
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    post.title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canEdit && onEdit != null)
                  IconButton(
                    icon: Icon(Icons.edit_outlined, size: 18, color: NixColors.textSecondary),
                    tooltip: 'Editar tópico',
                    onPressed: onEdit,
                  ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: NixColors.textSecondary),
                  tooltip: 'Fechar Tópico',
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Conteúdo do Tópico + Galeria de Fotos + Comentários
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  post.title,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: post.tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: NixColors.surfaceActive,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: _ForumTagLabel(channelId: post.channelId, label: t),
                          ))
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: NixColors.surfaceBorder),
                ),

                // Post Original (OP)
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: NixColors.surfaceActive,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          post.authorName[0],
                          style: TextStyle(
                              color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorName,
                      style: TextStyle(
                          color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: NixColors.textPrimary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'OP',
                        style:
                            TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (post.editedAt != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(editado)',
                        style: TextStyle(
                          color: NixColors.textMuted,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                ChatInlineText(
                  post.description,
                  style: TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),

                // Galeria de Fotos do Post no Split-View
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: post.images.length,
                  itemBuilder: (context, idx) {
                    final img = post.images[idx];
                    final photo = img.image;
                    if (photo != null) return Image.memory(photo.bytes, fit: BoxFit.contain);
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: NixColors.surfaceBorderStrong),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(img.code, style: NixTokens.monoCode()),
                          const Spacer(),
                          const Center(
                            child: Icon(Icons.image_outlined, size: 28, color: Colors.white30),
                          ),
                          const Spacer(),
                          Text(
                            img.label,
                            style: TextStyle(
                                color: NixColors.textPrimary, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            img.subtitle,
                            style: TextStyle(color: NixColors.textMuted, fontSize: 9.5),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text('RESPOSTAS DA COMUNIDADE (${post.comments.length})',
                    style: NixTokens.labelUppercase()),
                const SizedBox(height: 10),

                ...post.comments.map((c) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                c.senderName,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.senderFingerprint.substring(0, 9),
                                style: NixTokens.monoCode(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.text,
                            style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),

          // Input inferior do Split-Chat ("Send a message in ...")
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: InterfaceWallpaperLayer.translucentPanelsOf(context)
                  ? NixColors.background.withValues(
                      alpha: InterfaceWallpaperLayer.panelOpacityOf(context))
                  : NixColors.background,
              border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    onSubmitted: (_) => onSendComment(),
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enviar mensagem em "${post.title}"...',
                      isDense: true,
                      fillColor: NixColors.surfaceCard,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: NixColors.textPrimary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: onSendComment,
                  icon: const Icon(Icons.send_rounded, size: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ForumTagLabel extends StatelessWidget {
  final String channelId;
  final String label;

  const _ForumTagLabel({required this.channelId, required this.label});

  @override
  Widget build(BuildContext context) {
    final symbol = context.select<NixState, String?>(
      (state) => state.forumTagsFor(channelId)[label],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (symbol != null) ...[
          NixSymbol(symbol, size: 13, color: NixColors.textSecondary),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
        )),
      ],
    );
  }
}
