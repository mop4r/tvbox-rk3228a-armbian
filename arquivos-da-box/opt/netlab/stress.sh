#!/bin/bash
# uso: stress.sh <minutos> <rotulo>   — exaustao de memoria+cpu+rede com log persistente
MIN=${1:-20}; TAG=${2:-teste}; L=/var/lib/stress/$TAG.log; D=/run/stressblob
mkdir -p $D; : > $L
log(){ echo "$(date +%H:%M:%S) $*" >> $L; sync $L; }
log "INICIO $TAG ${MIN}min dpll=$(python3 -c "import mmap,os,struct;m=mmap.mmap(os.open('/dev/mem',os.O_RDONLY|os.O_SYNC),0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0x110e0000);r=lambda o:struct.unpack('<I',m[o:o+4])[0];c0,c1=r(0xc),r(0x10);print(24*(c0&0xfff)//((c1&0x3f)*((c0>>12)&7)*((c1>>6)&7)))")MHz"
head -c 64M /dev/urandom > $D/blob; sha256sum $D/blob | cut -d' ' -f1 > $D/blob.sha; log "blob sha $(cat $D/blob.sha)"
(cd $D && exec python3 -m http.server 8099 >/dev/null 2>&1) & HS=$!
stress-ng --vm 2 --vm-bytes 120M --vm-method all --verify --cpu 2 --cpu-method all -t ${MIN}m --metrics-brief > /var/lib/stress/$TAG.stressng 2>&1 & SN=$!
( for i in $(seq 1 99); do memtester 200M 1 > /var/lib/stress/$TAG.memtester.$i 2>&1; grep -q FAILURE /var/lib/stress/$TAG.memtester.$i && echo "memtester FALHOU loop $i" >> $L; done ) & MT=$!
U=https://deb.debian.org/debian/dists/trixie/main/Contents-all.gz
REF=$(curl -s $U | sha256sum | cut -d' ' -f1); log "ref internet sha $REF"
( n=0; bad=0; while true; do n=$((n+1)); s=$(curl -s --max-time 120 $U | sha256sum | cut -d' ' -f1); [ "$s" != "$REF" ] && { bad=$((bad+1)); echo "$(date +%T) DOWNLOAD CORROMPIDO #$n" >> $L; }; echo "$n $bad" > /run/stress.dl; done ) & DL=$!
END=$(( $(date +%s) + MIN*60 ))
while [ $(date +%s) -lt $END ]; do
  t=$(( $(cat /sys/class/thermal/thermal_zone0/temp)/1000 )); f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  log "temp=${t}C cpu=$((f/1000))MHz load=$(cut -d' ' -f1 /proc/loadavg) livre=$(free -m | awk '/Mem/{print $7}')M dl=$(cat /run/stress.dl 2>/dev/null) dmesg_err=$(dmesg | grep -ciE 'error|bug|oops|corrupt|unable to handle')"
  sleep 10
done
kill $MT $DL $HS 2>/dev/null; pkill memtester; wait $SN
log "stress-ng: $(grep -iE 'fail|error|passed|successful' /var/lib/stress/$TAG.stressng | tr '\n' ' ')"
log "memtester: $(grep -l FAILURE /var/lib/stress/$TAG.memtester.* 2>/dev/null | wc -l) loops com falha de $(ls /var/lib/stress/$TAG.memtester.* | wc -l)"
log "FIM $TAG downloads(total corrompidos)=$(cat /run/stress.dl)"
