import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/transport_profile.dart';
import '../../state/nix_state.dart';

/// Modal para seleção e configuração do Perfil de Transporte e Privacidade (Seção 5).
class TransportProfileDialog extends StatefulWidget {
  final TransportModule initialModule;

  const TransportProfileDialog({
    super.key,
    this.initialModule = TransportModule.downloads,
  });

  static Future<void> show(BuildContext context, {TransportModule initialModule = TransportModule.downloads}) {
    return showDialog(
      context: context,
      builder: (ctx) => TransportProfileDialog(initialModule: initialModule),
    );
  }

  @override
  State<TransportProfileDialog> createState() => _TransportProfileDialogState();
}

class _TransportProfileDialogState extends State<TransportProfileDialog> {
  late TransportModule _selectedModule;
  late TransportProfileType _selectedProfile;
  late TextEditingController _customHostController;
  late TextEditingController _customPortController;

  @override
  void initState() {
    super.initState();
    _selectedModule = widget.initialModule;
    final nixState = context.read<NixState>();
    final prefs = nixState.settings.moduleTransportPreferences;
    _selectedProfile = prefs.getProfile(_selectedModule);
    _customHostController = TextEditingController(text: prefs.customSocksHost);
    _customPortController = TextEditingController(text: prefs.customSocksPort.toString());
  }

  @override
  void dispose() {
    _customHostController.dispose();
    _customPortController.dispose();
    super.dispose();
  }

  void _onModuleChanged(TransportModule mod) {
    final nixState = context.read<NixState>();
    final prefs = nixState.settings.moduleTransportPreferences;
    setState(() {
      _selectedModule = mod;
      _selectedProfile = prefs.getProfile(mod);
    });
  }

  Future<void> _selectProfile(TransportProfileType profile) async {
    if (profile == TransportProfileType.directHttps) {
      // Perfil D exige confirmação explícita do usuário (Seção 5.1)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161524),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aviso de Privacidade: Clearnet',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'A Conexão Direta HTTPS conecta aos servidores remotos fora da rede Tor.\n\n'
            '• Seu endereço IP real será visível aos servidores e provedores.\n'
            '• Sem proteção contra censura ou análise de tráfego.\n'
            '• Recomendado apenas para transferências públicas de alta velocidade sem requisitos de anonimato.',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Compreendo e Confirmo'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() {
      _selectedProfile = profile;
    });
  }

  Future<void> _savePreferences() async {
    final nixState = context.read<NixState>();
    final current = nixState.settings.moduleTransportPreferences;
    final port = int.tryParse(_customPortController.text.trim()) ?? 1080;
    final host = _customHostController.text.trim().isEmpty ? '127.0.0.1' : _customHostController.text.trim();

    final updated = current.setModuleProfile(_selectedModule, _selectedProfile).copyWith(
          customSocksHost: host,
          customSocksPort: port,
        );

    final newSettings = nixState.settings.copyWith(
      moduleTransportPreferences: updated,
    );

    nixState.updateSettings(newSettings);
    GlobalTransportRegistry.update(updated);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Perfil de transporte atualizado para ${_selectedModule.label}: ${_selectedProfile.label}'),
          backgroundColor: const Color(0xFF7C3AED),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2E2248)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.security_rounded, color: Color(0xFFA78BFA), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perfis de Transporte & Privacidade',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Controle estrito de isolamento de rede e proteção contra vazamentos',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Seletor de Módulo
              const Text(
                'MÓDULO CONFIGURADO',
                style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final mod in TransportModule.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selectedColor: const Color(0xFF7C3AED).withOpacity(0.35),
                          backgroundColor: const Color(0xFF1E1E2E),
                          labelStyle: TextStyle(
                            color: _selectedModule == mod ? Colors.white : const Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: _selectedModule == mod ? FontWeight.bold : FontWeight.normal,
                          ),
                          label: Text(mod.label),
                          selected: _selectedModule == mod,
                          onSelected: (_) => _onModuleChanged(mod),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Lista de Opções de Perfil
              Expanded(
                child: ListView(
                  children: [
                    _buildProfileOption(
                      type: TransportProfileType.onionV3Strict,
                      title: 'Perfil A — Onion v3 Estrito',
                      subtitle: 'Todo o tráfego via Tor. Apenas serviços .onion. Bloqueio total de nós de saída e clearnet. Máxima privacidade.',
                      icon: Icons.shield_rounded,
                      accentColor: const Color(0xFFA855F7),
                    ),
                    const SizedBox(height: 8),
                    _buildProfileOption(
                      type: TransportProfileType.torSocks5,
                      title: 'Perfil B — Tor SOCKS5 (Padrão Soberano)',
                      subtitle: 'Tráfego roteado via Tor SOCKS5 local (127.0.0.1:9050). Resolução remota de DNS. Fail-closed total em quedas.',
                      icon: Icons.vpn_lock_rounded,
                      accentColor: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 8),
                    _buildProfileOption(
                      type: TransportProfileType.customSocks5,
                      title: 'Perfil C — SOCKS5 Personalizado',
                      subtitle: 'Utiliza proxy SOCKS5 definido pelo usuário (VPN, túnel SSH local). Sem garantia Tor nativo.',
                      icon: Icons.settings_ethernet_rounded,
                      accentColor: const Color(0xFF38BDF8),
                    ),
                    if (_selectedProfile == TransportProfileType.customSocks5) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161524),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _customHostController,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                decoration: const InputDecoration(
                                  labelText: 'Host SOCKS5',
                                  labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _customPortController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                decoration: const InputDecoration(
                                  labelText: 'Porta',
                                  labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _buildProfileOption(
                      type: TransportProfileType.directHttps,
                      title: 'Perfil D — Conexão Direta HTTPS (Clearnet)',
                      subtitle: 'Sem Tor, sem proxy. Conexão direta de alta velocidade. Expõe o seu endereço IP real. Exige consentimento.',
                      icon: Icons.public_rounded,
                      accentColor: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Botões inferiores
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _savePreferences,
                    child: const Text('Aplicar ao Módulo', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileOption({
    required TransportProfileType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedProfile == type;
    return InkWell(
      onTap: () => _selectProfile(type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.12) : const Color(0xFF141320),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF27273A),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, color: accentColor, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
