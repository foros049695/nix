import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models/space.dart';
import '../core/models/channel.dart';
import '../core/models/message.dart';
import '../core/models/member.dart';
import '../core/models/call_state.dart';
import '../core/models/publication.dart';
import '../core/security/security_context.dart';
import 'mock_data.dart';

class NixState extends ChangeNotifier {
  late List<Space> _spaces;
  late Space _currentSpace;
  late Channel _currentChannel;
  late Map<String, List<Message>> _messages;
  late Map<String, List<Publication>> _publications;
  late List<Member> _members;
  CallState _callState = const CallState();
  final SecurityContext _securityContext = const SecurityContext();

  bool _isMembersPanelOpen = false;
  int _selectedEphemeralTimer = 0; // 0 = normal, 30, 300, 3600...
  Timer? _callTimer;

  NixState() {
    _spaces = MockData.getInitialSpaces();
    _currentSpace = _spaces.first;
    _currentChannel = _currentSpace.channels.first;
    _messages = MockData.getInitialMessages();
    _publications = MockData.getInitialPublications();
    _members = MockData.getInitialMembers();
  }

  // Getters
  List<Space> get spaces => _spaces;
  Space get currentSpace => _currentSpace;
  Channel get currentChannel => _currentChannel;
  List<Message> get currentMessages => _messages[_currentChannel.id] ?? [];
  List<Publication> get currentPublications => _publications[_currentChannel.id] ?? [];
  List<Member> get members => _members;
  CallState get callState => _callState;
  SecurityContext get securityContext => _securityContext;
  bool get isMembersPanelOpen => _isMembersPanelOpen;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;

  // Seleção de Espaço
  void selectSpace(Space space) {
    if (_currentSpace.id == space.id) return;
    _currentSpace = space;
    if (space.channels.isNotEmpty) {
      _currentChannel = space.channels.first;
    }
    notifyListeners();
  }

  // Seleção de Canal / Tópico
  void selectChannel(Channel channel) {
    _currentChannel = channel;
    notifyListeners();
  }

  // Envio de Mensagem
  void sendMessage(String text) {
    if (text.trim().isEmpty) return;

    final newMessage = Message(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      channelId: _currentChannel.id,
      senderName: _securityContext.myPersona,
      senderFingerprint: _securityContext.myFingerprint,
      isMe: true,
      text: text.trim(),
      timestamp: DateTime.now(),
      ephemeralSeconds: _selectedEphemeralTimer,
      remainingSeconds: _selectedEphemeralTimer,
      isVerified: true,
    );

    if (!_messages.containsKey(_currentChannel.id)) {
      _messages[_currentChannel.id] = [];
    }
    _messages[_currentChannel.id]!.add(newMessage);
    notifyListeners();
  }

  // Timer de Mensagem Efêmera
  void setEphemeralTimer(int seconds) {
    _selectedEphemeralTimer = seconds;
    notifyListeners();
  }

  // Controle de Chamadas / Voice Rooms
  void joinCall(Channel channel) {
    if (_callState.isConnected && _callState.activeChannelId == channel.id) {
      return;
    }

    _callTimer?.cancel();
    _callState = CallState(
      activeChannelId: channel.id,
      activeChannelName: channel.name,
      isConnected: true,
      isMuted: false,
      isDeafened: false,
      participants: _members.where((m) => m.isOnline).toList(),
      durationSeconds: 0,
    );

    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callState = _callState.copyWith(
        durationSeconds: _callState.durationSeconds + 1,
      );
      notifyListeners();
    });

    notifyListeners();
  }

  void leaveCall() {
    _callTimer?.cancel();
    _callState = const CallState();
    notifyListeners();
  }

  void toggleMute() {
    _callState = _callState.copyWith(isMuted: !_callState.isMuted);
    notifyListeners();
  }

  void toggleDeafen() {
    _callState = _callState.copyWith(
      isDeafened: !_callState.isDeafened,
      isMuted: !_callState.isDeafened ? true : _callState.isMuted,
    );
    notifyListeners();
  }

  // Alternar painel lateral de membros
  void toggleMembersPanel() {
    _isMembersPanelOpen = !_isMembersPanelOpen;
    notifyListeners();
  }

  // Criação de Canais
  void createChannel({
    required String name,
    required ChannelType type,
    required String topic,
    required String category,
  }) {
    final cleanName = name.replaceAll(' ', '-').toLowerCase();
    final newChannel = Channel(
      id: 'ch_${DateTime.now().millisecondsSinceEpoch}',
      spaceId: _currentSpace.id,
      name: cleanName,
      topic: topic.isNotEmpty ? topic : 'Novo tópico de discussão segura.',
      type: type,
      category: category,
    );

    final updatedChannels = List<Channel>.from(_currentSpace.channels)..add(newChannel);
    final updatedSpace = _currentSpace.copyWith(channels: updatedChannels);

    final spaceIndex = _spaces.indexWhere((s) => s.id == _currentSpace.id);
    if (spaceIndex != -1) {
      _spaces[spaceIndex] = updatedSpace;
      _currentSpace = updatedSpace;
      _currentChannel = newChannel;
    }

    notifyListeners();
  }

  // Criação de Espaços
  void createSpace({
    required String name,
    required String description,
    required String emoji,
  }) {
    final initials = name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    final newSpace = Space(
      id: 'space_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      initials: initials.isNotEmpty ? initials : 'NX',
      description: description,
      iconEmoji: emoji.isNotEmpty ? emoji : '🛡️',
      channels: [
        Channel(
          id: 'ch_geral_${DateTime.now().millisecondsSinceEpoch}',
          spaceId: 'space_${DateTime.now().millisecondsSinceEpoch}',
          name: 'geral',
          topic: 'Tópico principal deste espaço.',
          type: ChannelType.text,
          category: '💬 TÓPICOS DE TEXTO',
        ),
      ],
    );

    _spaces.add(newSpace);
    _currentSpace = newSpace;
    _currentChannel = newSpace.channels.first;
    notifyListeners();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }
}
