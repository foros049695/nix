# ADR 0009 — Reprodução local do Pager no desktop

O mesmo cofre guarda as referências locais das faixas também no Linux e no Windows. No desktop a seleção aceita arquivos WAV. O Linux usa o cliente de áudio `paplay`, do PulseAudio ou PipeWire Pulse. O Windows usa `System.Media.SoundPlayer`, disponível no Windows PowerShell. Os processos recebem somente arquivos locais selecionados pelo usuário. Os argumentos do Windows são fornecidos por variável de ambiente e o script é fixo. O player termina ao fechar a playlist.

O aplicativo informa quando o backend de áudio está indisponível. Os pacotes de piloto continuam compilando sem drivers ou bibliotecas de áudio adicionais. A confirmação audível usa uma máquina com saída de áudio.
