#!/usr/bin/env bash
# ==============================================================================
# publish_to_github.sh — Assistente de Criação e Publicação no GitHub
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "================================================="
echo "🐙 PROJETO NIX — Assistente de Publicação GitHub"
echo "================================================="

# 1. Garantir que o repositório git local esteja inicializado e com branch main
if [ ! -d ".git" ]; then
  echo "Inicializando repositório Git local..."
  git init -b main
  git add .
  git commit -m "feat: fundação inicial do Projeto Nix (Roadmap, Docs, VS Code e Arquitetura)"
fi

CURRENT_BRANCH=$(git branch --show-current || echo "main")
echo "Branch atual: $CURRENT_BRANCH"

# 2. Verificar se o GitHub CLI (gh) está disponível
if command -v gh >/dev/null 2>&1; then
  echo "✅ GitHub CLI ('gh') detectado!"
  echo "Deseja criar e publicar o repositório agora via 'gh'? (s/n)"
  read -r resposta
  if [[ "$resposta" =~ ^[Ss]$ ]]; then
    echo "Nome do repositório no GitHub (padrão: nix):"
    read -r repo_name
    repo_name="${repo_name:-nix}"

    echo "Visibilidade: (1) Público [Recomendado para Open Source] ou (2) Privado?"
    read -r visib
    visib_flag="--public"
    if [ "$visib" = "2" ]; then
      visib_flag="--private"
    fi

    echo "Criando repositório no GitHub..."
    gh repo create "$repo_name" "$visib_flag" --source=. --remote=origin --push
    echo "🎉 Repositório criado e publicado com sucesso no GitHub!"
    exit 0
  fi
fi

# 3. Se 'gh' não estiver disponível ou usuário preferir configuração direta:
echo ""
echo "Configuração manual de Remote GitHub:"
echo "Digite o seu nome de usuário no GitHub:"
read -r github_user

if [ -z "$github_user" ]; then
  echo "❌ Nome de usuário não fornecido."
  exit 1
fi

echo "Digite o nome do repositório no GitHub (padrão: nix):"
read -r repo_name
repo_name="${repo_name:-nix}"

echo "Escolha o método de conexão:"
echo "  1) HTTPS (ex: https://github.com/$github_user/$repo_name.git)"
echo "  2) SSH   (ex: git@github.com:$github_user/$repo_name.git)"
read -r metodo

if [ "$metodo" = "2" ]; then
  REMOTE_URL="git@github.com:$github_user/$repo_name.git"
else
  REMOTE_URL="https://github.com/$github_user/$repo_name.git"
fi

echo "Configurando remote 'origin' para: $REMOTE_URL"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"

echo ""
echo "🚀 Pronto! Para enviar para o seu GitHub:"
echo "  1. Certifique-se de que o repositório '$repo_name' foi criado na sua conta (https://github.com/new)"
echo "  2. Execute o comando:"
echo "     git push -u origin $CURRENT_BRANCH"
echo ""
echo "Deseja tentar fazer o push agora? (s/n)"
read -r push_now
if [[ "$push_now" =~ ^[Ss]$ ]]; then
  git push -u origin "$CURRENT_BRANCH"
fi
