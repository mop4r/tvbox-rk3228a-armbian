#!/usr/bin/env bash
# Roda o ExportarTudo.java (Ghidra headless) em todos os binários Rockchip de original/.
# Uso: bash analise/ghidra_scripts/exportar_todos.sh <pasta_projeto_ghidra_temporaria>
set -u
R="$(cd "$(dirname "$0")/../.." && pwd -W 2>/dev/null || pwd)"
P="$1"
mkdir -p "$P"
O="$R/original"
ALVOS=(
  "RKDevTool_2.96|$O/RKDevTool_Release_v2.96_zh/RKDevTool_Release_v2.96/RKDevTool.exe"
  "RKDevTool_2.96|$O/RKDevTool_Release_v2.96_zh/RKDevTool_Release_v2.96/bin/AFPTool.exe"
  "RKDevTool_2.96|$O/RKDevTool_Release_v2.96_zh/RKDevTool_Release_v2.96/bin/RKImageMaker.exe"
  "RKDevTool_2.86|$O/RKDevTool_Release_v2.86/RKDevTool_Release_v2.86/RKDevTool.exe"
  "RKDevTool_2.86|$O/RKDevTool_Release_v2.86/RKDevTool_Release_v2.86/bin/AFPTool.exe"
  "RKDevTool_2.86|$O/RKDevTool_Release_v2.86/RKDevTool_Release_v2.86/bin/RKImageMaker.exe"
  "DriverAssitant_5.14|$O/DriverAssitant_v5.14/DriverAssitant_v5.14/DriverInstall.exe"
  "DriverAssitant_5.14|$O/DriverAssitant_v5.14/DriverAssitant_v5.14/bin/x64/RKDrvPreinst_x64.exe"
  "DriverAssitant_5.14/rockusb_x64_win10|$O/DriverAssitant_v5.14/DriverAssitant_v5.14/Driver/x64/win10/rockusb.sys"
  "DriverAssitant_5.14/rockusb_x64_win7|$O/DriverAssitant_v5.14/DriverAssitant_v5.14/Driver/x64/win7/rockusb.sys"
)
roda() {
  local dest="$1" bin="$2" n="$3"
  cmd //c "C:\\tools\\ghidra\\support\\analyzeHeadless.bat" "$P" "p$n" -import "$bin" \
    -scriptPath "$R/analise/ghidra_scripts" -postScript ExportarTudo.java "$R/analise/$dest" \
    -deleteProject > "$P/log_$n.txt" 2>&1
  echo "$(grep -h 'ExportarTudo:' "$P/log_$n.txt" | sed 's/.*ExportarTudo: //; s/ (GhidraScript).*//') <- $bin"
}
i=0
for a in "${ALVOS[@]}"; do
  i=$((i+1))
  roda "${a%%|*}" "${a#*|}" "$i" &
  (( i % 4 == 0 )) && wait
done
wait
echo FIM
