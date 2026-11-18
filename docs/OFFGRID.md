# 📡 Comunicação Off-Grid: Rádio LoRa, Reticulum & ATAK — Nix

## 1. Topologia de Rádio & Adaptadores

O Nix suporta comunicação tática sem dependência de torres celulares ou internet:
- **Interfaces Suportadas:** Bluetooth Low Energy (BLE) pareado a transceivers LoRa (ex: nós Meshtastic com firmware homologado, RAK4631, Heltec v3) ou adaptadores RNode/KISS para a rede Reticulum.
- **Filtro Estrito de Rádio (Protobuf):** O tráfego de rádio é limitado a mensagens serializadas no schema `proto/nix/v1/radio.proto`.
  - **Tamanho Máximo do Pacote:** `< 240 bytes`.
  - **Mídias Bloqueadas:** Fotos, áudios, vídeos e anexos são sumariamente rejeitados antes de chegarem à fila de transmissão de rádio.
  - **Airtime & Duty Cycle:** O cliente implementa controle rígido de tempo de transmissão para respeitar normas regulatórias regionais (ex: 915 MHz, 868 MHz).

---

## 2. Mapas Offline (MapLibre / MBTiles)

- **Renderização Local:** O aplicativo cliente carrega camadas vetoriais e raster contidas em arquivos `.mbtiles` armazenados no dispositivo.
- **Zero Requisições Remotas:** No perfil off-grid e privado, nenhuma requisição HTTP/DNS para provedores de tiles externos é disparada.

---

## 3. Ponte ATAK-CIV (Cursor-on-Target)

- O Nix Client inclui um servidor local UDP em `127.0.0.1:4242`.
- Permite a troca de telemetria tática (Cursor-on-Target CoT XML/binário) com o aplicativo ATAK-CIV executando no mesmo dispositivo.
- **Consentimento Explicito:** O envio de coordenadas geográficas exige autorização pontual do usuário; não há exportação automática de GPS em segundo plano.
