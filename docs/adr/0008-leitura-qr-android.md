# ADR 0008 — Leitura de QR de convites no Android

## Decisão

Usar JourneyApps ZXing Android Embedded 4.3.0 (Apache-2.0) como biblioteca local de captura e decodificação. O Android pede permissão de câmera quando a pessoa aciona o leitor. A atividade abre somente no fluxo de convite, retorna texto e não persiste fotos. O cliente não usa Google Play Services para ler o QR.

O formulário preenche o texto lido e exige confirmação explícita para importar. Ele reutiliza a verificação Ed25519 e X3DH do convite colado manualmente. Links, pagamentos e outros formatos ficam fora desse fluxo. O Nix continua gerando o QR com `qr_flutter`.

## Verificação

O APK compila com a biblioteca e a suíte Flutter cobre o preenchimento do formulário sem importação automática. Permissão, foco e captura óptica precisam de Android com câmera.
