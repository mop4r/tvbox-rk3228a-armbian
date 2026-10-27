#!/bin/bash
# Atualizacao semanal do Pi-hole (core/web/FTL) com conferencia depois.
L=/var/log/pihole/atualizacao-semanal.log
exec > "$L" 2>&1
export PATH="$PATH:/usr/sbin:/usr/local/bin" PIHOLE_SKIP_OS_CHECK=true
echo "== $(date) antes: $(pihole -v 2>&1 | tr '\n' ' ')"
pihole -up; RC=$?
echo "== rc=$RC depois: $(pihole -v 2>&1 | tr '\n' ' ')"
sleep 15
ok(){ [ -n "$(dig +short +time=3 @127.0.0.1 google.com A | grep -E '^[0-9.]+$')" ] && [ "$(dig +short +time=3 @127.0.0.1 doubleclick.net A | tail -1)" = "0.0.0.0" ]; }
if ok; then echo "== conferencia OK (resolve e bloqueia)"; logger -t pihole-atualiza "ok rc=$RC"
else echo "== conferencia FALHOU, reiniciando pihole-FTL"; systemctl restart pihole-FTL; sleep 10
  if ok; then logger -t pihole-atualiza "recuperado apos restart (rc=$RC)"; else logger -p user.err -t pihole-atualiza "DNS QUEBRADO apos atualizacao, veja $L"; fi
fi
