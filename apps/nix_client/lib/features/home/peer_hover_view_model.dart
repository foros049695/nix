import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models/direct_message.dart';
import '../../state/nix_state.dart' show PeerCardHoverState;

/// ViewModel desacoplado para a máquina de estados de hover e clique do Card ID.
/// Isola o debounce de 90ms para evitar recomposições desnecessárias do NixState global.
class PeerHoverViewModel extends ChangeNotifier {
  ContactRequest? _hoveredContactRequest;
  PeerCardHoverState _peerHoverState = PeerCardHoverState.closed;
  String? _hoverLockoutRequestId;
  bool _isCursorOverHoverPreview = false;
  Timer? _hoverDebounceTimer;
  bool _disposed = false;

  ContactRequest? get hoveredContactRequest => _hoveredContactRequest;
  PeerCardHoverState get peerHoverState => _peerHoverState;
  String? get hoverLockoutRequestId => _hoverLockoutRequestId;
  bool get isCursorOverHoverPreview => _isCursorOverHoverPreview;

  void onRequestPeerHoverEnter(ContactRequest req) {
    if (_disposed) return;
    if (_hoverLockoutRequestId == req.id) return;
    _hoverDebounceTimer?.cancel();
    _peerHoverState = PeerCardHoverState.openingPending;
    _hoveredContactRequest = req;
    _peerHoverState = PeerCardHoverState.openByHover;
    notifyListeners();
  }

  void onRequestPeerHoverExit(ContactRequest req) {
    if (_disposed) return;
    if (_hoverLockoutRequestId == req.id) {
      _hoverLockoutRequestId = null;
    }
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = Timer(const Duration(milliseconds: 90), () {
      if (_disposed) return;
      if (!_isCursorOverHoverPreview &&
          _hoveredContactRequest?.id == req.id &&
          _peerHoverState != PeerCardHoverState.openByClick) {
        _hoveredContactRequest = null;
        _peerHoverState = PeerCardHoverState.closed;
        notifyListeners();
      }
    });
  }

  void setHoverOverPreviewCard(bool over) {
    if (_disposed) return;
    _isCursorOverHoverPreview = over;
    if (!over) {
      _hoverDebounceTimer?.cancel();
      _hoverDebounceTimer = Timer(const Duration(milliseconds: 90), () {
        if (_disposed) return;
        if (!_isCursorOverHoverPreview &&
            _peerHoverState == PeerCardHoverState.openByHover) {
          _hoveredContactRequest = null;
          _peerHoverState = PeerCardHoverState.closed;
          notifyListeners();
        }
      });
    }
  }

  void dismissHoveredPeerCard() {
    if (_disposed) return;
    _hoverDebounceTimer?.cancel();
    if (_hoveredContactRequest != null) {
      _hoverLockoutRequestId = _hoveredContactRequest!.id;
    }
    _peerHoverState = PeerCardHoverState.closingRequested;
    _hoveredContactRequest = null;
    _isCursorOverHoverPreview = false;
    _peerHoverState = PeerCardHoverState.closed;
    notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = null;
    _hoveredContactRequest = null;
    _peerHoverState = PeerCardHoverState.closed;
    _hoverLockoutRequestId = null;
    _isCursorOverHoverPreview = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = null;
    super.dispose();
  }
}
