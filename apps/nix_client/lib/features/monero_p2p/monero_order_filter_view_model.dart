import 'package:flutter/foundation.dart';
import '../../core/models/monero_order.dart';

/// ViewModel desacoplado para filtragem e visualização das ofertas do Mercado Monero P2P.
/// Isola as alterações de busca e seleção de filtros (tipo de oferta, moeda fiat e método de pagamento),
/// mantendo estrita separação em relação às operações de assinatura e chaves (Seed B isolada).
class MoneroOrderFilterViewModel extends ChangeNotifier {
  List<MoneroP2pOrder> _allOrders = const [];
  MoneroP2pSide _selectedSide = MoneroP2pSide.sell;
  CryptoAsset _selectedAsset = CryptoAsset.xmr;
  String _selectedFiat = 'BRL';
  String _selectedPaymentMethod = '';
  String _searchQuery = '';
  bool _disposed = false;

  MoneroOrderFilterViewModel({List<MoneroP2pOrder> initialOrders = const []})
      : _allOrders = initialOrders;

  MoneroP2pSide get selectedSide => _selectedSide;
  CryptoAsset get selectedAsset => _selectedAsset;
  String get selectedFiat => _selectedFiat;
  String get selectedPaymentMethod => _selectedPaymentMethod;
  String get searchQuery => _searchQuery;

  void updateOrders(List<MoneroP2pOrder> orders) {
    if (_disposed) return;
    _allOrders = orders;
    notifyListeners();
  }

  void setSelectedAsset(CryptoAsset? asset) {
    if (_disposed) return;
    final target = asset ?? CryptoAsset.xmr;
    if (_selectedAsset == target) return;
    _selectedAsset = target;
    notifyListeners();
  }

  void setSelectedSide(MoneroP2pSide side) {
    if (_disposed) return;
    if (_selectedSide == side) return;
    _selectedSide = side;
    notifyListeners();
  }

  void setSelectedFiat(String fiat) {
    if (_disposed) return;
    if (_selectedFiat == fiat) return;
    _selectedFiat = fiat;
    notifyListeners();
  }

  void setSelectedPaymentMethod(String method) {
    if (_disposed) return;
    if (_selectedPaymentMethod == method) return;
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_disposed) return;
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void resetFilters() {
    if (_disposed) return;
    _selectedSide = MoneroP2pSide.sell;
    _selectedAsset = CryptoAsset.xmr;
    _selectedFiat = 'BRL';
    _selectedPaymentMethod = '';
    _searchQuery = '';
    notifyListeners();
  }

  List<MoneroP2pOrder> get filteredOrders {
    final q = _searchQuery.trim().toLowerCase();
    return _allOrders.where((order) {
      if (order.isExpired) return false;
      if (order.side != _selectedSide) return false;
      if (order.asset != _selectedAsset) return false;
      if (order.fiatCurrency != _selectedFiat) return false;
      if (_selectedPaymentMethod.isNotEmpty && _selectedPaymentMethod != 'Todos') {
        if (!order.paymentMethod.toLowerCase().contains(_selectedPaymentMethod.toLowerCase())) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        final matchesTrader = order.traderName.toLowerCase().contains(q);
        final matchesNotes = order.notes.toLowerCase().contains(q);
        final matchesMethod = order.paymentMethod.toLowerCase().contains(q);
        if (!matchesTrader && !matchesNotes && !matchesMethod) return false;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
