# ADR 0007 — Markdown e apresentação local do Archive

## Decisão

Converter Markdown em HTML com o pacote Dart `markdown` e renderizar o HTML saneado com a árvore produzida por `html`. O cliente usa widgets Flutter e compartilha a apresentação entre prévia e leitura. A lista de tags e atributos do sanitizador continua sendo a fronteira de conteúdo do Archive. O renderer lê a árvore local, sem abrir URLs, executar scripts, criar elementos web ou carregar imagens externas. Os documentos antigos continuam usando os mesmos campos assinados.

## Dependências

Ambos os pacotes são distribuídos sob BSD-3-Clause e mantidos no ecossistema Dart. A imagem final gera o inventário de licenças junto aos outros pacotes Flutter. A implementação evita mais um motor de renderização dentro do aplicativo.

## Consequência

A conversão final faz parte da publicação antes da assinatura. A revisão e a verificação de documentos já publicados continuam a operar sobre os bytes canônicos originais. A apresentação usa formatos suportados e oferece endereços de links para cópia deliberada.
