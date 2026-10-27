#!/bin/bash
# 21/10/2026: utilitários leves (vnstat, chrony, etckeeper, needrestart, tmux, ncdu, iftop, nload)
# e chrony como servidor de hora para a casa e o Tailscale. Roda como root via scripts/box.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l

# não brigar com o unattended-upgrades pelo lock do dpkg
for i in $(seq 1 60); do
  fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break
  echo "dpkg ocupado, esperando ($i)"; sleep 10
done

apt-get update -q </dev/null
apt-get install -y -q vnstat chrony etckeeper needrestart tmux ncdu iftop nload </dev/null

# needrestart: só lista (nunca reinicia sozinho pihole/unbound/tailscale); kernel fica em hold de propósito
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/50-mopar.conf <<'EOF'
# 21/10/2026: só listar serviços com biblioteca velha; o kernel está em apt-mark hold de propósito
$nrconf{restart} = 'l';
$nrconf{kernelhints} = 0;
EOF

# chrony: NTP.br por IP (funciona mesmo com o relógio errado no boot, quando o DNS com TLS ainda falha)
# + pool por nome; serve hora para a LAN e para o Tailscale
mkdir -p /etc/chrony/conf.d /etc/chrony/sources.d
cat > /etc/chrony/sources.d/ntpbr.sources <<'EOF'
# NTP.br por IP (a.st1, b.st1, c.st1, d.st1 em 21/10/2026) e por nome
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
systemctl unmask fake-hwclock
systemctl enable fake-hwclock
fake-hwclock save

# etckeeper: primeiro retrato do /etc
git -C /etc config user.name >/dev/null 2>&1 || git -C /etc config user.name "pihole-box"
git -C /etc config user.email >/dev/null 2>&1 || git -C /etc config user.email "root@pihole-box"
etckeeper commit "utilitarios leves + chrony + fake-hwclock (21/10/2026)" </dev/null || true

systemctl enable --now vnstat
sleep 8
echo "=== conferência"
chronyc -n sources
chronyc tracking | grep -E "Reference|System time|Leap"
systemctl is-active chrony vnstat fake-hwclock systemd-timesyncd || true
git -C /etc log --oneline | head -3
free -m | head -2
