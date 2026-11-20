import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/nix_state.dart';

class RelaySettingsDialog extends StatefulWidget {
  final NixState state;

  const RelaySettingsDialog({super.key, required this.state});

  @override
  State<RelaySettingsDialog> createState() => _RelaySettingsDialogState();
}

class _RelaySettingsDialogState extends State<RelaySettingsDialog> {
  late final _address =
      TextEditingController(text: widget.state.relayAddress?.toString());
  final _readToken = TextEditingController();
  final _writeToken = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _address.dispose();
    _readToken.dispose();
    _writeToken.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.saveRelayConfiguration(
        address: _address.text,
        readToken: _readToken.text,
        writeToken: _writeToken.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Falha ao salvar os dados do relay no cofre.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mailbox = widget.state.localRelayMailboxId;
    return AlertDialog(
      scrollable: true,
      title: const Text('Relay de mensagens'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Peça ao operador para provisionar sua caixa postal. '
              'O Nix usa o Tor para acessar o endereço Onion informado aqui.'),
          if (mailbox.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mailbox));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Identificador da caixa postal copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar identificador da caixa postal'),
            ),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'URL Onion v3'),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          TextField(
            controller: _readToken,
            decoration:
                const InputDecoration(labelText: 'Credencial de leitura'),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            controller: _writeToken,
            decoration: const InputDecoration(
                labelText: 'Cota de escrita (se fornecida)'),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
            onPressed: _saving ? null : _save, child: const Text('Salvar')),
      ],
    );
  }
}
