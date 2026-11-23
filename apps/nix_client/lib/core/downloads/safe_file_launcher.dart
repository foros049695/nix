import 'package:flutter/material.dart';
import 'models/download_task.dart';

/// Modal de confirmação e inspeção de segurança antes da abertura de arquivos baixados.
/// Proteção estrita contra execução automática e infecção por binários arbitrários.
class SafeFileOpeningDialog extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onConfirmOpen;

  const SafeFileOpeningDialog({
    super.key,
    required this.task,
    required this.onConfirmOpen,
  });

  static Future<void> show(BuildContext context, DownloadTask task, VoidCallback onConfirmOpen) {
    return showDialog(
      context: context,
      builder: (ctx) => SafeFileOpeningDialog(
        task: task,
        onConfirmOpen: onConfirmOpen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDangerous = task.isExecutable;

    return AlertDialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDangerous ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6).withOpacity(0.4),
          width: 1.5,
        ),
      ),
      title: Row(
        children: [
          Icon(
            isDangerous ? Icons.warning_amber_rounded : Icons.shield_outlined,
            color: isDangerous ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isDangerous ? 'Alerta de Segurança (Arquivo Executável)' : 'Inspeção de Arquivo Baixado',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDangerous) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                ),
                child: const Text(
                  'ATENÇÃO: Este arquivo possui formato executável ou instalador que pode conter código arbitrário. O Nix nunca executa programas automaticamente.',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
            ],
            _buildField('Nome:', task.fileName),
            _buildField('Origem:', task.url),
            _buildField('Destino:', task.destinationPath),
            _buildField('Tamanho:', task.formattedProgressBytes),
            if (task.sha256Expected != null)
              _buildField('SHA-256 Esperado:', task.sha256Expected!),
            if (task.sha256Actual != null)
              _buildField('SHA-256 Verificado:', task.sha256Actual!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDangerous ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirmOpen();
          },
          child: Text(isDangerous ? 'Compreendo os Riscos e Abrir' : 'Abrir Arquivo'),
        ),
      ],
    );
  }

  Widget _buildField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
