# 📋 Declaração Pública de Privacidade — Projeto Nix

> **Versão:** 4.1-dev  
> **Referência Técnica:** Matriz de Privacidade (*The Hated One* — 21 IDs)

O Projeto Nix é desenvolvido sob a filosofia de **privacidade como direito inalienável**, rejeitando modelos de negócios baseados em vigilância, monetização de dados ou publicidade comportamental.

---

## 1. Princípios Operacionais Fundamentais

1. **Zero Coleta de Identificadores Civis:** A criação de contas no Nix é um processo 100% local e soberano. Não exigimos, solicitamos ou armazenamos números de telefone, e-mails, nomes reais, documentos civis ou agendas de contatos.
2. **Arquitetura Cega no Servidor (Blind Relay):** Os servidores de retransmissão (*relays*) operam como caixas cegas. Eles armazenam apenas envelopes criptografados opacos por até 7 dias e desconhecem a identidade do remetente, o conteúdo das mensagens ou as redes de contatos dos usuários.
3. **Ausência de Telemetria e SDKs de Rastreamento:** Nossos binários são estritamente livres de Google Analytics, Firebase, Sentry, Facebook App Events ou qualquer outra biblioteca de telemetria analítica de terceiros.
4. **Transporte Fail-Closed via Tor:** Por padrão, toda comunicação de rede ocorre exclusivamente através da rede Tor encapsulada em serviços Onion v3 (`.onion`). Se o circuito Tor falhar, todas as conexões de rede são bloqueadas para impedir vazamento acidental em rede aberta (clearnet).
5. **Separação Criptográfica Estrita (Seed A vs. Seed B):** As chaves de comunicação pessoal e publicação são mantidas matematicamente isoladas da carteira financeira Monero (XMR). O mensageiro não custodia chaves privadas de gastos nem monitora o histórico financeiro.

---

## 2. A Matriz de Privacidade (The Hated One — 21 Critérios)

O projeto avalia continuamente a conformidade de sua arquitetura contra os 21 critérios de privacidade verificável distribuídos em três pilares (Conta, Uso e Serviço):

* **Linkability (Desvinculação):** Garantia de que diferentes contas e interações no dispositivo não possam ser associadas matematicamente entre si ou rastreadas por provedores externos (IDs: `L-A`, `L-U`, `L-S`).
* **Identifiability (Desidentificação):** Operação completa sem PII (*Personally Identifiable Information*), com logs do servidor limpos de endereços IP e modo *fail-closed* contra desanonimização de rede (IDs: `I-A`, `I-U`, `I-S`).
* **Nonrepudiation (Negação Plausível):** Protocolo criptográfico que permite a qualquer interlocutor negar autoria formal de mensagens passadas após o encerramento da sessão assíncrona (IDs: `N-A`, `N-U`, `N-S`).
* **Detectability (Indetectabilidade):** Operação local sem necessidade de conexão a servidores centrais para geração de chaves e métricas agregadas sem identificadores (IDs: `D-A`, `D-U`, `D-S`).
* **Data Disclosure (Não-Divulgação de Dados):** Cofre local em disco protegido por SQLCipher, criptografia de ponta a ponta obrigatória e código aberto auditável (IDs: `DD-A`, `DD-U`, `DD-S`).
* **Unawareness (Consciência do Usuário):** Escopo restrito de chaves criptográficas, avisos explícitos antes de habilitar conexões locais (como Bluetooth ou Wi-Fi) e documentação transparente (IDs: `U-A`, `U-U`, `U-S`).
* **Noncompliance (Resistência à Coação):** Suporte a PIN de coação e destruição segura de material de chaves locais sob demanda (IDs: `C-A`, `C-U`, `C-S`).

Consulte [`docs/PRIVACY_MATRIX.md`](PRIVACY_MATRIX.md) para os procedimentos de teste e critérios de aceite detalhados de cada ID.

---

## 3. Limites e Transparência sobre o Anonimato

Reconhecemos com clareza os limites do software para não criar falsas sensações de segurança:

* **O Tor não neutraliza adversários globais:** Entidades capazes de monitorar simultaneamente o tráfego de entrada e saída da rede Tor podem realizar análises estatísticas e temporais avançadas para correlacionar comunicação.
* **Segurança do Endpoint:** A criptografia do Nix protege os dados em trânsito e em repouso no disco. Se o sistema operacional hospedeiro estiver infectado por malware residente (*keyloggers*, trojans de acesso remoto) ou for apreendido em estado desbloqueado, o aplicativo não pode garantir a confidencialidade do que é exibido na tela.
* **Exportação pelo Destinatário:** Uma vez que uma mensagem é entregue e descriptografada no dispositivo de destino, o destinatário tem a capacidade física de fotografar a tela ou copiar o texto. O Nix minimiza metadados, mas a confiança humana no interlocutor permanece indispensável.
