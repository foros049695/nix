import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/nix_colors.dart';

class RecommendationItem {
  final String title;
  final String? coverUrl;
  final String? itemId;

  const RecommendationItem({
    required this.title,
    this.coverUrl,
    this.itemId,
  });

  factory RecommendationItem.fromMap(Map<String, dynamic> map) {
    return RecommendationItem(
      title: map['title'] as String? ?? 'Obra',
      coverUrl: map['cover'] as String? ?? map['coverUrl'] as String? ?? map['image'] as String?,
      itemId: map['id'] as String?,
    );
  }
}

class NixMediaRecommendations extends StatelessWidget {
  final String title;
  final List<RecommendationItem> items;
  final void Function(RecommendationItem item)? onItemTap;

  const NixMediaRecommendations({
    super.key,
    required this.title,
    required this.items,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mais como $title',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final rec = items[index];
              return InkWell(
                onTap: onItemTap != null ? () => onItemTap!(rec) : null,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cartão 2:3 estilo pôster (Avatar / Breaking Bad)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 100,
                          height: 130,
                          color: const Color(0xFF1E1B2E),
                          child: rec.coverUrl != null && rec.coverUrl!.isNotEmpty
                              ? (rec.coverUrl!.startsWith('http')
                                  ? Image.network(
                                      rec.coverUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildFallbackPoster(rec.title),
                                    )
                                  : Image.file(
                                      File(rec.coverUrl!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildFallbackPoster(rec.title),
                                    ))
                              : _buildFallbackPoster(rec.title),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: NixColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackPoster(String title) {
    return Container(
      color: const Color(0xFF191724),
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
