import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/nix_colors.dart';

class CastMember {
  final String name;
  final String role;
  final String? imageUrl;

  const CastMember({
    required this.name,
    required this.role,
    this.imageUrl,
  });

  factory CastMember.fromMap(Map<String, dynamic> map) {
    return CastMember(
      name: map['name'] as String? ?? 'Ator',
      role: map['role'] as String? ?? map['character'] as String? ?? '',
      imageUrl: map['image'] as String? ?? map['imageUrl'] as String?,
    );
  }
}

class NixMediaCastCarousel extends StatelessWidget {
  final List<CastMember> cast;

  const NixMediaCastCarousel({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Elenco',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final member = cast[index];
              return SizedBox(
                width: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Retrato circular (Avatar / Breaking Bad style)
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1E1B2E),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.2,
                        ),
                      ),
                      child: ClipOval(
                        child: member.imageUrl != null && member.imageUrl!.isNotEmpty
                            ? (member.imageUrl!.startsWith('http')
                                ? Image.network(
                                    member.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildFallbackAvatar(member.name),
                                  )
                                : Image.file(
                                    File(member.imageUrl!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildFallbackAvatar(member.name),
                                  ))
                            : _buildFallbackAvatar(member.name),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      member.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: NixColors.textMuted,
                        fontSize: 10,
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

  Widget _buildFallbackAvatar(String name) {
    final initials = name.trim().split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join();
    return Center(
      child: Text(
        initials.isNotEmpty ? initials.toUpperCase() : 'NX',
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
