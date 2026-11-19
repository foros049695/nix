import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/github_repo.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/features/calls/call_view_model.dart';
import 'package:nix_client/features/discovery/starwire_filter_view_model.dart';
import 'package:nix_client/features/home/peer_hover_view_model.dart';
import 'package:nix_client/features/monero_p2p/monero_order_filter_view_model.dart';
import 'package:nix_client/state/nix_state.dart' show PeerCardHoverState;

void main() {
  group('CallViewModel Unit & Isolation Tests', () {
    test('starts disconnected and duration is 0', () {
      final vm = CallViewModel();
      expect(vm.callState.isConnected, isFalse);
      expect(vm.callState.durationSeconds, 0);
      expect(vm.callState.activeChannelId, isNull);
      vm.dispose();
    });

    test('joinCall starts 1-second interval timer and increments duration', () async {
      final vm = CallViewModel();
      const channel = Channel(
        id: 'voice_1',
        spaceId: 'space_1',
        name: 'Voz Geral',
        topic: 'Canal de voz geral',
        category: 'Geral',
        type: ChannelType.voice,
      );

      int notificationCount = 0;
      vm.addListener(() {
        notificationCount++;
      });

      vm.joinCall(channel);
      expect(vm.callState.isConnected, isTrue);
      expect(vm.callState.activeChannelId, 'voice_1');
      expect(vm.callState.activeChannelName, 'Voz Geral');
      expect(notificationCount, 1);

      // Aguarda 2.1 segundos para verificar o timer de 1 Hz
      await Future<void>.delayed(const Duration(milliseconds: 2150));
      expect(vm.callState.durationSeconds, greaterThanOrEqualTo(2));
      expect(notificationCount, greaterThanOrEqualTo(3));

      // Teste de mute / deafen
      vm.toggleMute();
      expect(vm.callState.isMuted, isTrue);
      vm.toggleDeafen();
      expect(vm.callState.isDeafened, isTrue);

      // Desconectar encerra o timer e zera o estado
      vm.leaveCall();
      expect(vm.callState.isConnected, isFalse);
      expect(vm.callState.durationSeconds, 0);

      final countBeforeWait = notificationCount;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      // Garante que o timer parou de notificar
      expect(notificationCount, countBeforeWait);

      vm.dispose();
      // Chamar pós-dispose não pode lançar exceção
      expect(() => vm.leaveCall(), returnsNormally);
      expect(() => vm.toggleMute(), returnsNormally);
    });

    test('reset cleans up state and cancels active timer', () async {
      final vm = CallViewModel();
      const channel = Channel(
        id: 'voice_2',
        spaceId: 'space_1',
        name: 'Voz Privada',
        topic: 'Canal privado',
        category: 'Privado',
        type: ChannelType.voice,
      );
      vm.joinCall(channel);
      expect(vm.callState.isConnected, isTrue);

      vm.reset();
      expect(vm.callState.isConnected, isFalse);
      expect(vm.callState.durationSeconds, 0);
      vm.dispose();
    });
  });

  group('PeerHoverViewModel Unit & Debounce Tests', () {
    test('initial state has no hovered request', () {
      final vm = PeerHoverViewModel();
      expect(vm.hoveredContactRequest, isNull);
      expect(vm.peerHoverState, PeerCardHoverState.closed);
      vm.dispose();
    });

    test('onRequestPeerHoverEnter and dismissHoveredPeerCard', () async {
      final vm = PeerHoverViewModel();
      final req = ContactRequest(
        id: 'req_1',
        peerName: 'Alice',
        peerPublicId: 'NIX-ALICE123',
        note: 'Olá',
        timestamp: DateTime.now(),
      );

      vm.onRequestPeerHoverEnter(req);
      expect(vm.hoveredContactRequest?.id, 'req_1');
      expect(vm.peerHoverState, PeerCardHoverState.openByHover);

      // Dismiss imediato
      vm.dismissHoveredPeerCard();
      expect(vm.hoveredContactRequest, isNull);
      expect(vm.peerHoverState, PeerCardHoverState.closed);

      vm.dispose();
      expect(() => vm.dismissHoveredPeerCard(), returnsNormally);
    });

    test('onRequestPeerHoverExit closes after 90ms debounce if not over preview card', () async {
      final vm = PeerHoverViewModel();
      final req = ContactRequest(
        id: 'req_2',
        peerName: 'Bob',
        peerPublicId: 'NIX-BOB456',
        note: 'Olá Bob',
        timestamp: DateTime.now(),
      );

      vm.onRequestPeerHoverEnter(req);
      expect(vm.hoveredContactRequest?.id, 'req_2');

      vm.onRequestPeerHoverExit(req);
      // Aguarda 110ms para o timer de 90ms disparar
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(vm.hoveredContactRequest, isNull);
      expect(vm.peerHoverState, PeerCardHoverState.closed);

      vm.dispose();
    });
  });

  group('StarwireFilterViewModel Filtering & Aggregation Tests', () {
    final sampleRepos = [
      GithubRepository(
        id: '1',
        name: 'nix',
        owner: 'foros049695',
        description: 'Sovereign private P2P ecosystem',
        language: 'Dart',
        starsCount: 1200,
        forksCount: 45,
        license: 'MIT',
        topics: const ['cryptography', 'privacy', 'mesh'],
        htmlUrl: 'https://github.com/foros049695/nix',
        updatedDate: DateTime(2026, 11, 19),
        isTrending: true,
      ),
      GithubRepository(
        id: '2',
        name: 'monero-wallet',
        owner: 'monero',
        description: 'Privacy coin wallet',
        language: 'C++',
        starsCount: 4500,
        forksCount: 300,
        license: 'BSD-3-Clause',
        topics: const ['cryptography', 'monero'],
        htmlUrl: 'https://github.com/monero/wallet',
        updatedDate: DateTime(2026, 11, 18),
        isTrending: false,
      ),
      GithubRepository(
        id: '3',
        name: 'tor-proxy',
        owner: 'tor',
        description: 'Onion routing tunnel',
        language: 'Rust',
        starsCount: 3200,
        forksCount: 120,
        license: 'GPL-3.0',
        topics: const ['tor', 'privacy'],
        htmlUrl: 'https://github.com/tor/proxy',
        updatedDate: DateTime(2026, 11, 10),
        isTrending: false,
      ),
    ];

    test('initial calculation and category/language counts', () {
      final vm = StarwireFilterViewModel(initialRepos: sampleRepos);
      expect(vm.filteredRepos.length, 3);
      expect(vm.languageCounts['Dart'], 1);
      expect(vm.languageCounts['C++'], 1);
      expect(vm.languageCounts['Rust'], 1);
      vm.dispose();
    });

    test('search query filtering', () {
      final vm = StarwireFilterViewModel(initialRepos: sampleRepos);
      vm.setSearchQuery('sovereign');
      expect(vm.filteredRepos.length, 1);
      expect(vm.filteredRepos.first.name, 'nix');

      vm.setSearchQuery('monero');
      expect(vm.filteredRepos.length, 1);
      expect(vm.filteredRepos.first.name, 'monero-wallet');

      vm.setSearchQuery('');
      expect(vm.filteredRepos.length, 3);
      vm.dispose();
    });

    test('topic and language filtering and sorting', () {
      final vm = StarwireFilterViewModel(initialRepos: sampleRepos);
      vm.setSelectedTopic('cryptography');
      expect(vm.filteredRepos.length, 2);

      vm.setSelectedLanguage('Dart');
      expect(vm.filteredRepos.length, 1);
      expect(vm.filteredRepos.first.name, 'nix');

      vm.resetFilters();
      expect(vm.filteredRepos.length, 3);

      vm.setSortBy('stars');
      expect(vm.filteredRepos.first.starsCount, 4500);

      vm.dispose();
      expect(() => vm.setSearchQuery('test'), returnsNormally);
    });
  });

  group('MoneroOrderFilterViewModel Filtering Tests', () {
    final List<MoneroP2pOrder> sampleOrders = [
      MoneroP2pOrder(
        id: 'order_1',
        traderName: 'Alice',
        traderPublicId: 'NIX-ALICE',
        side: MoneroP2pSide.sell,
        fiatCurrency: 'BRL',
        pricePerXmr: 850.0,
        minFiatLimit: 50.0,
        maxFiatLimit: 2000.0,
        paymentMethod: 'PIX',
        notes: 'PIX rápido',
        signatureHex: 'mock_sig_1',
        signedManifestHash: 'manifest_hash_1',
        isSignatureVerified: true,
      ),
      MoneroP2pOrder(
        id: 'order_2',
        traderName: 'Bob',
        traderPublicId: 'NIX-BOB',
        side: MoneroP2pSide.buy,
        fiatCurrency: 'USD',
        pricePerXmr: 160.0,
        minFiatLimit: 100.0,
        maxFiatLimit: 5000.0,
        paymentMethod: 'SEPA',
        notes: 'SEPA transfer',
        signatureHex: 'mock_sig_2',
        signedManifestHash: 'manifest_hash_2',
        isSignatureVerified: true,
      ),
      MoneroP2pOrder(
        id: 'order_3',
        traderName: 'Charlie',
        traderPublicId: 'NIX-CHARLIE',
        side: MoneroP2pSide.sell,
        fiatCurrency: 'USD',
        pricePerXmr: 162.0,
        minFiatLimit: 50.0,
        maxFiatLimit: 1000.0,
        paymentMethod: 'Cash',
        notes: 'Cash in hand',
        signatureHex: 'mock_sig_3',
        signedManifestHash: 'manifest_hash_3',
        isSignatureVerified: true,
      ),
    ];

    test('initial calculation and side filtering', () {
      final vm = MoneroOrderFilterViewModel(initialOrders: sampleOrders);
      // Padrão do ViewModel é sell e BRL
      expect(vm.filteredOrders.length, 1);
      expect(vm.filteredOrders.first.traderName, 'Alice');

      vm.setSelectedFiat('USD');
      expect(vm.filteredOrders.length, 1);
      expect(vm.filteredOrders.first.traderName, 'Charlie');

      vm.setSelectedSide(MoneroP2pSide.buy);
      expect(vm.filteredOrders.length, 1);
      expect(vm.filteredOrders.first.traderName, 'Bob');

      vm.dispose();
    });

    test('fiat, payment method and search filtering', () {
      final vm = MoneroOrderFilterViewModel(initialOrders: sampleOrders);
      vm.setSelectedFiat('USD');
      vm.setSelectedSide(MoneroP2pSide.sell);
      expect(vm.filteredOrders.length, 1);

      vm.setSelectedPaymentMethod('Cash');
      expect(vm.filteredOrders.length, 1);
      expect(vm.filteredOrders.first.traderName, 'Charlie');

      vm.setSearchQuery('hand');
      expect(vm.filteredOrders.length, 1);

      vm.setSearchQuery('nonexistent');
      expect(vm.filteredOrders.isEmpty, isTrue);

      vm.resetFilters();
      // Reset retorna para sell e BRL
      expect(vm.filteredOrders.length, 1);

      vm.dispose();
      expect(() => vm.setSelectedFiat('EUR'), returnsNormally);
    });
  });
}
