import 'package:flutter/foundation.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/message.dart';

/// ViewModel desacoplado para chats, mensagens, composição e filtros de conversa (Etapa 8).
class ChatViewModel extends ChangeNotifier {
  DirectMessageThread? _selectedDm;
  Message? _replyingToMessage;
  Message? _editingMessage;
  final Set<String> _selectedMessageIds = {};
  String? _highlightedMessageId;
  String _conversationHistorySearch = '';
  int _selectedEphemeralTimer = 0;

  List<DirectMessageThread> _directMessages = [];
  Map<String, List<Message>> _messages = {};

  ChatViewModel({
    List<DirectMessageThread>? initialDirectMessages,
    Map<String, List<Message>>? initialMessages,
  })  : _directMessages = initialDirectMessages != null ? List.from(initialDirectMessages) : [],
        _messages = initialMessages != null ? Map.from(initialMessages) : {};

  // Getters
  DirectMessageThread? get selectedDm => _selectedDm;
  Message? get replyingToMessage => _replyingToMessage;
  Message? get editingMessage => _editingMessage;
  Set<String> get selectedMessageIds => Set.unmodifiable(_selectedMessageIds);
  String? get highlightedMessageId => _highlightedMessageId;
  String get conversationHistorySearch => _conversationHistorySearch;
  int get selectedEphemeralTimer => _selectedEphemeralTimer;
  List<DirectMessageThread> get directMessages => List.unmodifiable(_directMessages);
  Map<String, List<Message>> get messages => Map.unmodifiable(_messages);

  List<Message> getMessagesForChannel(String channelId) =>
      _messages[channelId] ?? const [];

  void setDirectMessages(List<DirectMessageThread> threads) {
    _directMessages = List.from(threads);
    notifyListeners();
  }

  void setMessages(Map<String, List<Message>> messagesMap) {
    _messages = Map.from(messagesMap);
    notifyListeners();
  }

  void selectDm(DirectMessageThread? dm) {
    if (_selectedDm?.id != dm?.id) {
      _selectedDm = dm;
      _replyingToMessage = null;
      _editingMessage = null;
      _selectedMessageIds.clear();
      _highlightedMessageId = null;
      notifyListeners();
    }
  }

  void setReplyingToMessage(Message? message) {
    if (_replyingToMessage != message) {
      _replyingToMessage = message;
      if (message != null) _editingMessage = null;
      notifyListeners();
    }
  }

  void setEditingMessage(Message? message) {
    if (_editingMessage != message) {
      _editingMessage = message;
      if (message != null) _replyingToMessage = null;
      notifyListeners();
    }
  }

  void toggleMessageSelection(String messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
    } else {
      _selectedMessageIds.add(messageId);
    }
    notifyListeners();
  }

  void selectAllMessages(Iterable<String> messageIds) {
    _selectedMessageIds.addAll(messageIds);
    notifyListeners();
  }

  void clearMessageSelection() {
    if (_selectedMessageIds.isNotEmpty) {
      _selectedMessageIds.clear();
      notifyListeners();
    }
  }

  void setHighlightedMessageId(String? id) {
    if (_highlightedMessageId != id) {
      _highlightedMessageId = id;
      notifyListeners();
    }
  }

  void setConversationHistorySearch(String query) {
    if (_conversationHistorySearch != query) {
      _conversationHistorySearch = query;
      notifyListeners();
    }
  }

  void setSelectedEphemeralTimer(int seconds) {
    if (_selectedEphemeralTimer != seconds) {
      _selectedEphemeralTimer = seconds;
      notifyListeners();
    }
  }

  void addMessage(String channelOrThreadId, Message message) {
    final list = List<Message>.from(_messages[channelOrThreadId] ?? const []);
    list.add(message);
    _messages[channelOrThreadId] = list;

    // Atualiza preview na lista de DMs se aplicável
    final dmIndex = _directMessages.indexWhere((dm) => dm.id == channelOrThreadId);
    if (dmIndex != -1) {
      final dm = _directMessages[dmIndex];
      final updatedDmMessages = List<Message>.from(dm.messages)..add(message);
      _directMessages[dmIndex] = dm.copyWith(
        messages: updatedDmMessages,
        unreadCount: message.isMe ? dm.unreadCount : dm.unreadCount + 1,
      );
    }

    notifyListeners();
  }

  void updateMessage(String channelOrThreadId, Message updatedMessage) {
    final list = _messages[channelOrThreadId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == updatedMessage.id);
      if (index != -1) {
        final updatedList = List<Message>.from(list);
        updatedList[index] = updatedMessage;
        _messages[channelOrThreadId] = updatedList;
        notifyListeners();
      }
    }
  }

  void deleteMessage(String channelOrThreadId, String messageId) {
    final list = _messages[channelOrThreadId];
    if (list != null) {
      final updatedList = list.where((m) => m.id != messageId).toList();
      _messages[channelOrThreadId] = updatedList;
      _selectedMessageIds.remove(messageId);
      if (_replyingToMessage?.id == messageId) _replyingToMessage = null;
      if (_editingMessage?.id == messageId) _editingMessage = null;
      notifyListeners();
    }
  }

  void markThreadRead(String threadId) {
    final dmIndex = _directMessages.indexWhere((dm) => dm.id == threadId);
    if (dmIndex != -1 && _directMessages[dmIndex].unreadCount > 0) {
      _directMessages[dmIndex] = _directMessages[dmIndex].copyWith(unreadCount: 0);
      notifyListeners();
    }
  }

  void resetComposer() {
    _replyingToMessage = null;
    _editingMessage = null;
    _selectedMessageIds.clear();
    _highlightedMessageId = null;
    notifyListeners();
  }
}
