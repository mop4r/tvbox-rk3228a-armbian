#!/bin/bash
# Roda um script local na TV box como root (sudo), via plink, lendo o acesso do .env do mq.
#
# Uso:  box.sh <script.sh>            -> roda o script na box (stdin)
#       box.sh -c '<comando>'          -> roda um comando curto
#       T=300 box.sh <script.sh>       -> timeout em segundos (padrao 120)
#       BOX_IP=100.x.y.z box.sh .. -> forca o IP (ex.: pelo Tailscale, fora de casa)
#
# Credenciais: ~/workspace/scripts/multiclaude-queue/credenciais/rk322x-flash/.env
# (fora do git, mas sincronizado entre os PCs pelo sync desde 22/10/2026).
set -e
ENV="$HOME/workspace/scripts/multiclaude-queue/credenciais/rk322x-flash/.env"
[ -f "$ENV" ] || { echo "faltando $ENV (pedir a senha do usuario mopar ao Pedro)" >&2; exit 2; }
# shellcheck disable=SC1090
. "$ENV"
PLINK="/c/Program Files/PuTTY/plink.exe"
IP="${BOX_IP:-$BOX_IP_LAN}"
# fora da rede de casa, cai para o Tailscale
if ! timeout 3 bash -c "echo > /dev/tcp/$IP/22" 2>/dev/null; then IP="$BOX_IP_TAILSCALE"; fi
HK="${BOX_HOSTKEY_OVERRIDE:-$BOX_HOSTKEY}"
run(){ timeout "${T:-120}" "$PLINK" -ssh -batch -hostkey "$HK" -pw "$BOX_PASS" "$BOX_USER@$IP" "sudo -S -p '' bash -s" 2>&1; }
if [ "$1" = "-c" ]; then
  { echo "$BOX_PASS"; echo "$2"; } | run
else
  { echo "$BOX_PASS"; cat "$1"; } | run
fi
