#!/bin/bash
# 21/10/2026: configuração dos utilitários depois do apt (needrestart, chrony, fake-hwclock, etckeeper, vnstat).
# A instalação fica em instalar-utilitarios-2026-10-21.sh. Este é idempotente; roda como root via scripts/box.sh.
set -uo pipefail

# needrestart: só lista (nunca reinicia sozinho pihole/unbound/tailscale); kernel fica em hold de propósito
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/50-mopar.conf <<'EOF'
# 21/10/2026: só listar serviços com biblioteca velha; o kernel está em apt-mark hold de propósito
$nrconf{restart} = 'l';
$nrconf{kernelhints} = 0;
EOF

# chrony: NTP.br por IP (funciona com o relógio errado no boot, quando o DNS com TLS ainda falha)
# + pool por nome; serve hora para a LAN e para o Tailscale
mkdir -p /etc/chrony/conf.d /etc/chrony/sources.d
cat > /etc/chrony/sources.d/ntpbr.sources <<'EOF'
# NTP.br por IP (a.st1, b.st1, d.st1 em 21/10/2026) e por nome
server 200.160.7.186 iburst
server 201.49.148.135 iburst
server 200.20.186.76 iburst
pool pool.ntp.br iburst maxsources 2
EOF
cat > /etc/chrony/conf.d/mopar.conf <<'EOF'
# sem RTC: pode corrigir o relógio de uma vez a qualquer momento
makestep 1 -1
# servidor de hora para a casa e o Tailscale
allow 192.168.0.0/16
allow 100.64.0.0/10
EOF
systemctl restart chrony </dev/null

# fake-hwclock guarda a hora entre um boot e outro (o timesyncd fazia isso e saiu com o chrony)
systemctl unmask fake-hwclock </dev/null
systemctl enable fake-hwclock </dev/null
fake-hwclock save

systemctl enable --now vnstat </dev/null

git -C /etc config user.name >/dev/null 2>&1 || git -C /etc config user.name "pihole-box"
git -C /etc config user.email >/dev/null 2>&1 || git -C /etc config user.email "root@pihole-box"
etckeeper commit "utilitarios leves + chrony + fake-hwclock (21/10/2026)" </dev/null >/dev/null 2>&1

sleep 10
echo "=== conferência"
dpkg --audit && echo "dpkg integro"
for p in vnstat chrony etckeeper needrestart tmux ncdu iftop nload; do dpkg-query -W -f='${Status} ${Package} ${Version}\n' "$p"; done
chronyc -n sources
chronyc tracking | grep -E "Reference|System time|Leap"
echo "chrony=$(systemctl is-active chrony) vnstat=$(systemctl is-active vnstat) fake-hwclock=$(systemctl is-enabled fake-hwclock) timesyncd=$(systemctl is-active systemd-timesyncd)"
ss -lunp | grep -E ":123 " || echo "chrony sem porta 123?"
git -C /etc log --oneline | head -3
free -m | head -2
echo FIM-CONFIG
