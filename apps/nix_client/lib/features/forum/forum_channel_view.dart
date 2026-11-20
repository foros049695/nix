import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/forum_post.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../chat/message_header.dart';

/// Visualização de Canal de Tópicos / Fórum Interativo (Inspirado nas Imagens 9 e 10).
/// Exibe grade de cartões com fotos 2x2 e abre um Split-Chat interativo lateral ao selecionar um tópico.
class ForumChannelView extends StatefulWidget {
  final Channel channel;

  const ForumChannelView({super.key, required this.channel});

  @override
  State<ForumChannelView> createState() => _ForumChannelViewState();
}

class _ForumChannelViewState extends State<ForumChannelView> {
  String _searchQuery = '';
  String _selectedTag = 'Todos';
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitComment(NixState state, String postId) {
    final text = _commentController.text;
    if (text.trim().isNotEmpty) {
      state.addForumComment(postId, text);
      _commentController.clear();
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
                      color: NixColors.background,
                      child: Column(
                        children: [
                          // Barra de Busca + Botão Novo Tópico
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    onChanged: (v) => setState(() => _searchQuery = v),
                                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13.5),
                                    decoration: InputDecoration(
                                      hintText: 'Pesquisar ou criar um tópico...',
                                      prefixIcon:
                                          Icon(Icons.search_rounded, color: NixColors.textMuted),
                                      fillColor: NixColors.surfaceCard,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: NixColors.textPrimary,
                                    foregroundColor: Colors.black,
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: NixTokens.borderSm),
                                  ),
                                  onPressed: () => _showCreateTopicModal(context, nixState),
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                  label: const Text(
                                    'Novo Tópico',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
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
                                return InkWell(
                                  onTap: () => setState(() => _selectedTag = tag),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? NixColors.textPrimary : NixColors.surfaceCard,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? NixColors.textPrimary : NixColors.surfaceBorder,
                                      ),
                                    ),
                                    child: Text(
                                      tags.containsKey(tag) ? '${tags[tag]} $tag' : tag,
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : NixColors.textSecondary,
                                        fontSize: 11.5,
                                        fontWeight:
                                            isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Grade de Cartões de Tópicos (Estilo Imagens 9 e 10)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, gridConstraints) {
                                final cols = gridConstraints.maxWidth > 760
                                    ? 3
                                    : (gridConstraints.maxWidth > 460 ? 2 : 1);
                                return GridView.builder(
                                  padding: const EdgeInsets.all(18),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    mainAxisExtent: 310,
                                  ),
                                  itemCount: filteredPosts.length,
                                  itemBuilder: (context, idx) {
                                    final post = filteredPosts[idx];
                                    final isSelected = selectedPost?.id == post.id;
                                    return _ForumPostCard(
                                      post: post,
                                      isSelected: isSelected,
                                      onTap: () => nixState.selectForumPost(post),
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
    var icon = '';
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
          TextField(
            maxLength: 8,
            onChanged: (value) => icon = value,
            decoration: const InputDecoration(labelText: 'Ícone ou emoji'),
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

  void _showCreateTopicModal(BuildContext context, NixState state) {
    var title = '';
    var description = '';
    String? chosenTag;
    final tags = state.forumTagsFor(widget.channel.id);

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
                      label: Text('${tags[t]} $t', style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: NixColors.textPrimary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : NixColors.textPrimary,
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
                  onChanged: (value) => title = value,
                  decoration: const InputDecoration(hintText: 'ex: Análise de Antena 915MHz...'),
                ),
                const SizedBox(height: 12),
                Text('DESCRIÇÃO / ESPECIFICAÇÕES', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (value) => description = value,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Inclua peso, dimensões, hash ou observações...',
                  ),
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
                backgroundColor: NixColors.textPrimary,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (title.trim().isNotEmpty) {
                  state.createForumPost(
                    title: title,
                    description: description,
                    tags: [if (chosenTag != null) chosenTag!],
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Publicar Tópico', style: TextStyle(fontWeight: FontWeight.bold)),
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

  const _ForumPostCard({
    required this.post,
    required this.isSelected,
    required this.onTap,
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
            color: isSelected ? NixColors.textPrimary : NixColors.surfaceBorderStrong,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Autor + Badge NEW
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${post.authorName} · há ${DateTime.now().difference(post.createdAt).inHours.clamp(1, 24)}h',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                        child: Text(
                          post.tags.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 10),
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

  const _SplitThreadPanel({
    required this.post,
    required this.commentController,
    required this.onSendComment,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
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
                            child: Text(t,
                                style:
                                    TextStyle(color: NixColors.textSecondary, fontSize: 11)),
                          ))
                      .toList(),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
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
                  ],
                ),
                const SizedBox(height: 10),
                Text(
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
              color: NixColors.background,
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
