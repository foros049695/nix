import 'package:flutter/material.dart';
import '../theme/nix_colors.dart';

enum ChannelType {
  text,         // Sala de texto padrão
  forum,        // Área de tópicos interativos (cards com imagens + chat em split-view)
  voice,        // Sala de voz / call E2EE
  publication,  // Sala do Nix Archive (artigos canônicos e evidências)
  announcement, // Canal de comunicados
}

class Channel {
  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelType type;
  final int unreadCount;
  final bool isEncrypted;
  final String category;

  const Channel({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.topic,
    required this.type,
    this.unreadCount = 0,
    this.isEncrypted = true,
    required this.category,
  });

  IconData get icon {
    switch (type) {
      case ChannelType.text:
        return Icons.tag_rounded;
      case ChannelType.forum:
        return Icons.forum_outlined;
      case ChannelType.voice:
        return Icons.volume_up_outlined;
      case ChannelType.publication:
        return Icons.menu_book_outlined;
      case ChannelType.announcement:
        return Icons.campaign_outlined;
    }
  }

  // Ícones monocromáticos consistentes
  Color get iconColor => NixColors.iconSecondary;
}
