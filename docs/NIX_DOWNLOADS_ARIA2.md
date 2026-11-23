# Nix Downloads — Gerenciador com aria2 e Segmentação HTTP/HTTPS

## 1. Visão Geral

O **Nix Downloads** é a central de transferências de arquivos diretos do Projeto Nix, projetada com foco em alta velocidade, privacidade e segurança operacional.

---

## 2. Decisão Definitiva: aria2 Apenas para HTTP e HTTPS

> ⚠️ **Decisão de Segurança:** O binário `aria2c` é configurado e restrito para operar **exclusivamente com downloads diretos HTTP e HTTPS**.

As seguintes funcionalidades do aria2 foram explicitamente desativadas via flags de linha de comando e no controlador RPC:
- `--enable-dht=false`: Desativa rede DHT pública.
- `--enable-peer-exchange=false`: Desativa troca de peers (PEX).
- `--follow-torrent=false`: Impede a resolução automática de arquivos torrent.
- `--follow-metalink=false`: Impede o download encadeado via Metalink.
- Proibição de métodos RPC `aria2.addTorrent` e `aria2.addMetalink`.
- Validação em tempo de execução: URLs com esquemas `magnet:`, `dht:`, `torrent:`, `file:` são sumariamente rejeitadas.

### Por que BitTorrent via Tor é bloqueado?
Conforme amplamente documentado pelo Tor Project, o tráfego BitTorrent frequentemente vaza o endereço IP real do usuário através de pacotes UDP/DHT e requisições diretas a trackers fora do túnel SOCKS5. Para garantir que o Nix permaneça 100% à prova de vazamento de identidade, o aplicativo permite **pesquisar e copiar links magnet**, mas não baixa enxames BitTorrent internamente.

---

## 3. Downloads Segmentados (HTTP Range Requests)

Para acelerar transferências diretas em servidores que suportam partial content (RFC 7233), o Nix utiliza segmentação paralela:
- `--split=4`: 4 conexões concorrentes por download.
- `--max-connection-per-server=4`: Respeita os servidores upstream sem gerar sobrecarga abusiva.
- `--min-split-size=1M`: Segmentação ativa apenas para arquivos maiores que 1 MB.
- `--continue=true`: Retomada automática de downloads pausados ou interrompidos.

---

## 4. Fallback Nativo em Puro Dart (`DartSegmentedDownloader`)

Em plataformas onde o binário compilado `aria2c` não está presente (como em determinados dispositivos Android ou distribuições mínimas), o Nix ativa transparentemente o motor nativo `DartSegmentedDownloader`:
1. Envia requisição `HEAD` para verificar o cabeçalho `Accept-Ranges: bytes` e `Content-Length`.
2. Se suportado, divide o intervalo de bytes em fatias e executa downloads paralelos utilizando `Range: bytes=start-end`.
3. Salva arquivos de segmento temporários (`.part0`, `.part1`, etc.), permitindo pausar e retomar sem perder o progresso.
4. Concatena os segmentos no arquivo final e valida a soma criptográfica SHA-256 caso informada.

---

## 5. Inspeção de Segurança Antes da Abertura de Arquivos

Arquivos com extensões potencialmente executáveis (`.exe`, `.sh`, `.bat`, `.cmd`, `.apk`, `.bin`, `.msi`, `.deb`) acionam o diálogo `SafeFileOpeningDialog`:
- Apresenta o nome do arquivo, tipo MIME e tamanho real.
- Exibe a URL de origem e o caminho de destino no disco local.
- Apresenta o hash SHA-256 verificado.
- Exige confirmação explícita do usuário antes de permitir a abertura pelo sistema operacional.
- O Nix **nunca executa nem descompacta arquivos automaticamente**.
