import 'member.dart';

class CallState {
  final String? activeChannelId;
  final String? activeChannelName;
  final bool isConnected;
  final bool isMuted;
  final bool isDeafened;
  final List<Member> participants;
  final int durationSeconds;

  const CallState({
    this.activeChannelId,
    this.activeChannelName,
    this.isConnected = false,
    this.isMuted = false,
    this.isDeafened = false,
    this.participants = const [],
    this.durationSeconds = 0,
  });

  CallState copyWith({
    String? activeChannelId,
    String? activeChannelName,
    bool? isConnected,
    bool? isMuted,
    bool? isDeafened,
    List<Member>? participants,
    int? durationSeconds,
  }) {
    return CallState(
      activeChannelId: activeChannelId ?? this.activeChannelId,
      activeChannelName: activeChannelName ?? this.activeChannelName,
      isConnected: isConnected ?? this.isConnected,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      participants: participants ?? this.participants,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}
