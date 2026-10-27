#!/bin/bash
# Instala o Uptime Kuma na TV box (Armbian trixie, armv7) como serviço próprio, sem Docker.
# Roda como root (box.sh). Idempotente: rodar de novo só atualiza para a versão em VERSAO.
# Escuta só em 127.0.0.1 até o administrador ser criado; depois o vigiar-kuma.sh libera a rede.
set -euo pipefail
VERSAO="${VERSAO:-2.5.6}"
DIR=/opt/uptime-kuma
export DEBIAN_FRONTEND=noninteractive

echo "== pacotes (Node do Debian, atualizado pelo unattended-upgrades)"
apt-get install -y -q nodejs npm git >/dev/null
node -v

id kuma >/dev/null 2>&1 || useradd --system --home-dir /var/lib/uptime-kuma --create-home --shell /usr/sbin/nologin kuma

echo "== código $VERSAO"
if [ ! -d "$DIR/.git" ]; then
  git clone --quiet --depth 1 --branch "$VERSAO" https://github.com/louislam/uptime-kuma.git "$DIR"
else
  git -C "$DIR" fetch --quiet --depth 1 origin tag "$VERSAO"
  git -C "$DIR" checkout --quiet "$VERSAO"
fi
chown -R kuma:kuma "$DIR"

echo "== dependências (pode demorar: armv7 e 1 GB de RAM)"
cd "$DIR"
sudo -u kuma -H env NODE_OPTIONS=--max-old-space-size=384 npm ci --omit=dev --no-audit --no-fund --loglevel=error
echo "== interface pronta (dist)"
sudo -u kuma -H npm run download-dist --silent

echo "== serviço"
cat > /etc/systemd/system/uptime-kuma.service <<'EOF'
[Unit]
Description=Uptime Kuma (vigia da casa)
After=network-online.target
Wants=network-online.target

[Service]
User=kuma
WorkingDirectory=/opt/uptime-kuma
Environment=NODE_ENV=production
Environment=DATA_DIR=/var/lib/uptime-kuma/data/
EnvironmentFile=-/etc/default/uptime-kuma
ExecStart=/usr/bin/node server/server.js
Restart=on-failure
RestartSec=10
# Sem acesso a mais do que precisa
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/uptime-kuma /opt/uptime-kuma
ProtectHome=true
PrivateTmp=true
MemoryMax=350M

[Install]
WantedBy=multi-user.target
EOF
# Antes de criar o administrador: só localhost.
[ -f /etc/default/uptime-kuma ] || echo 'UPTIME_KUMA_HOST=127.0.0.1' > /etc/default/uptime-kuma
echo 'UPTIME_KUMA_PORT=3001' >> /etc/default/uptime-kuma
sort -u -o /etc/default/uptime-kuma /etc/default/uptime-kuma
systemctl daemon-reload
systemctl enable --now uptime-kuma
sleep 20
systemctl is-active uptime-kuma
ss -ltn | grep 3001 || true
echo "fim"
