import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/direct_message.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Barra lateral da Área Inicial de Conversas Privadas (Estilo Discord Home — Imagem 4).
class HomeSidebar extends StatefulWidget {
  const HomeSidebar({super.key});

  @override
  State<HomeSidebar> createState() => _HomeSidebarState();
}

class _HomeSidebarState extends State<HomeSidebar> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final activeTab = nixState.homeSubTab;
    final selectedDm = nixState.selectedDm;

    final filteredDms = nixState.directMessages.where((dm) {
      if (_searchQuery.trim().isEmpty) return true;
      return dm.peerName.toLowerCase().contains(_searchQuery.trim().toLowerCase());
    }).toList();

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(right: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Column(
        children: [
          // Topo: Busca rápida ("Find or start a conversation")
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Encontrar ou iniciar conversa',
                hintStyle: const TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: NixColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                fillColor: NixColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: NixColors.surfaceBorder),
                ),
              ),
            ),
          ),

          // Abas Superiores: Card ID, Friends, Requests, Transações, Updates + Lista de DMs
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                _navTile(
                  icon: Icons.badge_outlined,
                  label: 'Card ID (Identidade)',
                  isSelected: activeTab == HomeSubTab.cardId,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.cardId),
                ),
                _navTile(
                  icon: Icons.people_outline_rounded,
                  label: 'Amigos',
                  isSelected: activeTab == HomeSubTab.friends,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.friends),
                ),
                _navTile(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Solicitações',
                  badgeCount: nixState.contactRequests.length,
                  isSelected: activeTab == HomeSubTab.requests,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.requests),
                ),
                _navTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Transações (XMR)',
                  isSelected: activeTab == HomeSubTab.transactions,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.transactions),
                ),
                _navTile(
                  icon: Icons.bolt_outlined,
                  label: 'Atualizações',
                  isSelected: activeTab == HomeSubTab.updates,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.updates),
                ),

                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MENSAGENS DIRETAS', style: NixTokens.labelUppercase()),
                      const Icon(Icons.add, size: 14, color: NixColors.textMuted),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Lista de Conversas Privadas
                ...filteredDms.map((dm) {
                  final isSelected =
                      activeTab == HomeSubTab.directChat && selectedDm?.id == dm.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? NixColors.surfaceActive : Colors.transparent,
                      borderRadius: NixTokens.borderSm,
                      border: isSelected
                          ? Border.all(color: NixColors.surfaceBorderStrong)
                          : null,
                    ),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: () => nixState.selectDirectMessage(dm),
                      leading: Stack(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              shape: BoxShape.circle,
                              border: Border.all(color: NixColors.surfaceBorderStrong),
                            ),
                            child: Center(
                              child: Text(
                                dm.peerName[0],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: dm.isOnline ? Colors.white : NixColors.textDim,
                                shape: BoxShape.circle,
                                border: Border.all(color: NixColors.surfaceSidebar, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        dm.peerName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : NixColors.textSecondary,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        dm.statusText,
                        style: const TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: dm.unreadCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${dm.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),

          // Rodapé de Perfil do Usuário (Com botão rápido para Configurações)
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: NixColors.surfaceDock,
              border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => nixState.openProfileOverlay(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white38),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/nix_logo_128.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.person, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => nixState.openProfileOverlay(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nixState.userProfile.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Invisível · Onion',
                          style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18, color: NixColors.textSecondary),
                  tooltip: 'Configurações do Sistema',
                  onPressed: () => nixState.openProfileOverlay(startInSettings: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isSelected ? NixColors.surfaceActive : Colors.transparent,
        borderRadius: NixTokens.borderSm,
        border: isSelected ? Border.all(color: NixColors.surfaceBorderStrong) : null,
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        leading: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : NixColors.iconSecondary,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : NixColors.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        trailing: badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
