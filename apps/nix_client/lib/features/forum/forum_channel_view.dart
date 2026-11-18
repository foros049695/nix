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

  final List<String> _availableTags = const [
    'Todos',
    'Hardware',
    'Eletrônicos',
    'Segurança',
    'Reviews',
    'Audiovisual',
    'Outros',
  ];

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
    final selectedPost = nixState.selectedForumPost;

    final filteredPosts = allPosts.where((post) {
      final matchesTag = _selectedTag == 'Todos' || post.tags.contains(_selectedTag);
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
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                    decoration: const InputDecoration(
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
                                    backgroundColor: Colors.white,
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

                          // Barra de Tags / Filtros
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              itemCount: _availableTags.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (context, idx) {
                                final tag = _availableTags[idx];
                                final isSelected = _selectedTag == tag;
                                return InkWell(
                                  onTap: () => setState(() => _selectedTag = tag),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : NixColors.surfaceCard,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? Colors.white : NixColors.surfaceBorder,
                                      ),
                                    ),
                                    child: Text(
                                      tag,
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

  void _showCreateTopicModal(BuildContext context, NixState state) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String chosenTag = 'Hardware';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Criar Novo Tópico no Fórum'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TAG DO TÓPICO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _availableTags.where((t) => t != 'Todos').map((t) {
                    final selected = chosenTag == t;
                    return ChoiceChip(
                      label: Text(t, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => setModalState(() => chosenTag = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text('TÍTULO DO TÓPICO', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: 'ex: Análise de Antena 915MHz...'),
                ),
                const SizedBox(height: 12),
                Text('DESCRIÇÃO / ESPECIFICAÇÕES', style: NixTokens.labelUppercase()),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
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
              child: const Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (titleCtrl.text.trim().isNotEmpty) {
                  state.createForumPost(
                    title: titleCtrl.text,
                    description: descCtrl.text,
                    tags: [chosenTag],
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
            color: isSelected ? Colors.white : NixColors.surfaceBorderStrong,
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
                    style: const TextStyle(color: NixColors.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (post.isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
              style: const TextStyle(
                color: Colors.white,
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
                        border: Border.all(color: Colors.white12, width: 0.5),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              Icons.photo_camera_back_outlined,
                              size: 22,
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 4,
                            child: Text(
                              img.code,
                              style: const TextStyle(
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
                              style: const TextStyle(
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
                          style: const TextStyle(color: NixColors.textSecondary, fontSize: 10),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 6),
                const Icon(Icons.mode_comment_outlined, size: 12, color: NixColors.textMuted),
                const SizedBox(width: 3),
                Text(
                  '${post.comments.length}',
                  style: const TextStyle(color: NixColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
      decoration: const BoxDecoration(
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
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    post.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: NixColors.textSecondary),
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
                  style: const TextStyle(
                    color: Colors.white,
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
                                    const TextStyle(color: NixColors.textSecondary, fontSize: 11)),
                          ))
                      .toList(),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: NixColors.surfaceBorder),
                ),

                // Post Original (OP)
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: NixColors.surfaceActive,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          post.authorName[0],
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                  style: const TextStyle(
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
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            img.subtitle,
                            style: const TextStyle(color: NixColors.textMuted, fontSize: 9.5),
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
                                style: const TextStyle(
                                  color: Colors.white,
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
                            style: const TextStyle(color: NixColors.textSecondary, fontSize: 12.5),
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
            decoration: const BoxDecoration(
              color: NixColors.background,
              border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    onSubmitted: (_) => onSendComment(),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
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
                    backgroundColor: Colors.white,
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
