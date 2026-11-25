import 'dart:io';
import 'package:flutter/material.dart';

class TrailerItem {
  final String title;
  final String? thumbnailUrl;
  final String? videoUrl;

  const TrailerItem({
    required this.title,
    this.thumbnailUrl,
    this.videoUrl,
  });

  factory TrailerItem.fromMap(Map<String, dynamic> map) {
    return TrailerItem(
      title: map['title'] as String? ?? 'Trailer Oficial',
      thumbnailUrl: map['thumbnail'] as String? ?? map['thumbnailUrl'] as String?,
      videoUrl: map['url'] as String? ?? map['videoUrl'] as String?,
    );
  }
}

class NixMediaTrailers extends StatelessWidget {
  final List<TrailerItem> trailers;

  const NixMediaTrailers({super.key, required this.trailers});

  @override
  Widget build(BuildContext context) {
    if (trailers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trailers',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 135,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: trailers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final trailer = trailers[index];
              return SizedBox(
                width: 175,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card 16:9 com thumbnail e botão play central
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 98,
                        width: 175,
                        color: const Color(0xFF1E1B2E),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (trailer.thumbnailUrl != null && trailer.thumbnailUrl!.isNotEmpty) ...[
                              if (trailer.thumbnailUrl!.startsWith('http'))
                                Image.network(
                                  trailer.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
                                )
                              else
                                Image.file(
                                  File(trailer.thumbnailUrl!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
                                ),
                            ] else
                              _buildFallbackThumbnail(),

                            // Overlay escurecido
                            Container(color: Colors.black.withValues(alpha: 0.25)),

                            // Ícone play translúcido
                            Center(
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white38, width: 1.2),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      trailer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      color: const Color(0xFF191724),
      child: const Center(
        child: Icon(
          Icons.videocam_outlined,
          color: Colors.white24,
          size: 32,
        ),
      ),
    );
  }
}
