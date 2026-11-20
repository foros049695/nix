import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models/call_state.dart';
import '../../core/models/channel.dart';
import '../../core/models/member.dart';

/// ViewModel desacoplado para gerenciamento do ciclo de vida e estado das chamadas de voz.
/// Isola o temporizador de 1 segundo (1 Hz) para evitar reconstruções desnecessárias no NixState global.
class CallViewModel extends ChangeNotifier {
  CallState _callState = const CallState();
  Timer? _callTimer;
  bool _disposed = false;

  CallState get callState => _callState;
  bool get isConnected => _callState.isConnected;
  bool get isMuted => _callState.isMuted;
  bool get isDeafened => _callState.isDeafened;
  int get durationSeconds => _callState.durationSeconds;

  void joinCall(Channel channel, {List<Member> onlineMembers = const []}) {
    if (_disposed) return;
    if (_callState.isConnected && _callState.activeChannelId == channel.id) {
      return;
    }

    _callTimer?.cancel();
    _callState = CallState(
      activeChannelId: channel.id,
      activeChannelName: channel.name,
      isConnected: true,
      isMuted: _callState.isMuted,
      isDeafened: false,
      participants: onlineMembers,
      durationSeconds: 0,
    );

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _callState = _callState.copyWith(
        durationSeconds: _callState.durationSeconds + 1,
      );
      notifyListeners();
    });

    notifyListeners();
  }

  void leaveCall() {
    if (_disposed) return;
    _callTimer?.cancel();
    _callTimer = null;
    _callState = CallState(isMuted: _callState.isMuted);
    notifyListeners();
  }

  void toggleMute() {
    if (_disposed) return;
    final muted = !_callState.isMuted;
    _callState = _callState.copyWith(
      isMuted: muted, isDeafened: muted && _callState.isDeafened,
    );
    notifyListeners();
  }

  void restoreMicrophone(bool muted) {
    if (_disposed || muted == _callState.isMuted) return;
    _callState = _callState.copyWith(isMuted: muted);
    notifyListeners();
  }

  void toggleDeafen() {
    if (_disposed) return;
    final newDeafened = !_callState.isDeafened;
    _callState = _callState.copyWith(
      isDeafened: newDeafened,
      isMuted: newDeafened ? true : _callState.isMuted,
    );
    notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    _callTimer?.cancel();
    _callTimer = null;
    _callState = const CallState();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _callTimer?.cancel();
    _callTimer = null;
    super.dispose();
  }
}
