#!/bin/bash
# Caixa-preta: a cada 30s grava o estado da box no eMMC (sync), para diagnosticar travamentos.
D=/var/lib/blackbox; mkdir -p $D
while true; do
  F=$D/$(date +%F).log
  t=$(( $(cat /sys/class/thermal/thermal_zone0/temp)/1000 ))
  f=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)/1000 ))
  m=$(awk '/MemAvailable/{a=$2}/SwapTotal/{st=$2}/SwapFree/{sf=$2}END{printf "%dM swap=%dM",a/1024,(st-sf)/1024}' /proc/meminfo)
  io=$(awk '$3=="mmcblk2"{printf "rd=%s wr=%s io_fila=%s ms_io=%s",$4,$8,$12,$13}' /proc/diskstats)
  S=/sys/class/net/end0/statistics; n="rx_err=$(cat $S/rx_errors) tx_err=$(cat $S/tx_errors) rx_drop=$(cat $S/rx_dropped) tx_drop=$(cat $S/tx_dropped) mac=$(cat /sys/class/net/end0/address)"
  dq=$( { /usr/bin/time -f %e dig +tries=1 +time=3 @127.0.0.1 pi.hole A >/dev/null; } 2>&1 | tail -1 )
  dst=$(ps -eo pid,stat,wchan:22,comm --no-headers | awk '$2 ~ /^D/{printf "%s(%s:%s) ",$4,$1,$3}')
  echo "$(date +%T) up=$(cut -d' ' -f1 /proc/uptime)s load=$(cut -d' ' -f1-3 /proc/loadavg | tr ' ' /) temp=${t}C cpu=${f}MHz livre=$m $io $n dns=${dq}s D=[${dst}]" >> $F
  sync $F
  find $D -name '*.log' -mtime +30 -delete
  sleep 30
done
