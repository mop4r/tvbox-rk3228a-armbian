#!/bin/bash
# uso: bench.sh <servidor[#porta]> <lista> [passadas]
S=$1; L=$2; P=${3:-1}; H=${S%#*}; PT=53; [[ $S == *#* ]] && PT=${S#*#}
for p in $(seq 1 $P); do
  T=(); F=0
  while read -r d; do [ -z "$d" ] && continue
    q=$(dig +tries=1 +time=2 -p $PT @$H "$d" A 2>/dev/null | awk '/Query time/{print $4}')
    [ -z "$q" ] && { F=$((F+1)); continue; }; T+=($q)
  done < "$L"
  printf '%s\n' "${T[@]}" | sort -n | awk -v s="$S" -v p=$p -v f=$F '{a[NR]=$1; t+=$1} END{printf "%-22s passada%d  n=%d falhas=%d  media=%.0fms  mediana=%dms  p90=%dms  max=%dms\n", s,p,NR,f,t/NR,a[int(NR*0.5)+1],a[int(NR*0.9)],a[NR]}'
done
