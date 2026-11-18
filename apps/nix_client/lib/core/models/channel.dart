import 'package:flutter/material.dart';

enum ChannelType {
  text,        // Sala de texto / tópico de discussão
  voice,       // Sala de voz / call tática
  publication, // Sala do Nix Archive (artigos canônicos e evidências)
  announcement // Tópico de comunicados somente leitura
}

class Channel {
  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelType type;
  final int unreadCount;
  final bool isEncrypted;
  final String category; // ex: "TÓPICOS DE TEXTO", "SALAS DE VOZ", "ARQUIVO"

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
        return Icons.tag;
      case ChannelType.voice:
        return Icons.volume_up_rounded;
      case ChannelType.publication:
        return Icons.auto_stories_rounded;
      case ChannelType.announcement:
        return Icons.campaign_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case ChannelType.text:
        return const Color(0xFF9CA3AF);
      case ChannelType.voice:
        return const Color(0xFF10B981);
      case ChannelType.publication:
        return const Color(0xFFF59E0B);
      case ChannelType.announcement:
        return const Color(0xFF00B0FF);
    }
  }
}
