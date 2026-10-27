#!/bin/bash
# Monitor de rede: 1 linha por minuto em /var/lib/netmon/AAAA-MM-DD.csv
# alvo: media_ms;max_ms;perda%  (5 pings) + tempo de DNS (Pi-hole e Claro) com nome nao cacheado
D=/var/lib/netmon; F=$D/$(date +%F).csv
[ -f $F ] || echo "hora;roteador;claro_1o_salto;cloudflare_1.1.1.1;google_8.8.8.8;facebook;dns_pihole_ms;dns_claro_ms" > $F
p(){ ping -c 5 -i 0.2 -W 2 -q $1 2>/dev/null | awk -F'[/ ]' '/packet loss/{for(i=1;i<=NF;i++) if($i ~ /%$/) l=$i} /rtt/{a=$8; m=$9} END{printf "%s;%s;%s", (a?a:"-"), (m?m:"-"), (l?l:"100%")}'; }
d(){ r=$(dig +tries=1 +time=3 @$1 "$(date +%s%N | tail -c 8).netmon-teste.com.br" A 2>/dev/null | awk '/Query time/{print $4}'); echo "${r:-timeout}"; }
echo "$(date +%T);$(p 192.168.0.1);$(p 177.143.216.1);$(p 1.1.1.1);$(p 8.8.8.8);$(p www.facebook.com);$(d 127.0.0.1);$(d 181.213.132.2)" >> $F
find $D -name '*.csv' -mtime +30 -delete
