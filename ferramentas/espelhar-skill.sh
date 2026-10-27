#!/bin/bash
# Copia a skill tvbox-rk3228a (fonte única da documentação) para este repositório.
# Rodar depois de qualquer mudança na skill; em seguida: python -I ferramentas/publicar.py "mensagem"
# (gera a versão limpa em publico/ e sobe). Nunca copiar de publico/ ou do GitHub para cá.
set -euo pipefail
S="${SKILL:-$HOME/workspace/scripts/skills/tvbox-rk3228a}"
R="$(cd "$(dirname "$0")/.." && pwd)"
cp "$S"/references/*.md "$R/docs/"
rm -rf "$R/arquivos-da-box" && cp -r "$S/arquivos-da-box" "$R/"
cp "$S"/ferramentas/* "$R/ferramentas/"
cp "$S/scripts/box.sh" "$R/scripts/"
echo "skill espelhada em $R"
