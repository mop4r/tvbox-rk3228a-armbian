#!/bin/bash
# Auto-instalador com LOG COMPLETO. Grava o Armbian no eMMC, aplica led-conf7 (HDMI R29),
# sinaliza por LED e TELA, e registra TUDO no cartao (MULTITOOL/autoflash.log) continuamente.

LED="/sys/class/leds/led:state1"
set_led(){ echo "$1" > "$LED/trigger" 2>/dev/null; }

TTY=/dev/tty1
MTPART=$(blkid --label "MULTITOOL" -l 2>/dev/null)
BOOTDEV=$(lsblk -n -o PKNAME "$MTPART" 2>/dev/null)
LOG=/tmp/autoflash.log
: > "$LOG"

# escreve no log, na tela e (se montado) copia para o cartao
flush_to_card(){ [ -d /mnt/images ] && cp "$LOG" /mnt/autoflash.log 2>/dev/null; sync; }
say(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG" > "$TTY" 2>/dev/null; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; flush_to_card; }

# TUDO (stdout+stderr, com trace) tambem vai para o log
exec 2>>"$LOG"
set -x

printf '\n\n==== AUTO-FLASH (log completo) ====\n' > "$TTY" 2>/dev/null
say "=== INICIO ==="
say "data=$(date)  kernel=$(uname -r)"
say "cartao(SD)=$BOOTDEV  MTPART=$MTPART"

# estado completo do sistema no log
{
  echo "----- lsblk -----"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  echo "----- /proc/partitions -----"; cat /proc/partitions
  echo "----- /sys/bus/mmc/devices -----"
  for d in /sys/bus/mmc/devices/*; do echo "$d: type=$(cat $d/type 2>/dev/null) name=$(cat $d/name 2>/dev/null) block=$(ls $d/block 2>/dev/null)"; done
  echo "----- blkid -----"; blkid
  echo "----- ip addr -----"; ip addr 2>/dev/null
  echo "----- dmesg (boot do kernel) -----"; dmesg
} >> "$LOG" 2>&1
flush_to_card

# monta a particao de imagens
mount "$MTPART" /mnt 2>/dev/null
say "images disponiveis: $(ls /mnt/images 2>/dev/null)"

# acha o eMMC (tipo MMC, != SD de boot)
EMMC=""
for d in /sys/bus/mmc/devices/*; do
    t=$(cat "$d/type" 2>/dev/null); blk=$(ls "$d/block" 2>/dev/null | head -1)
    say "  mmc $d type=$t block=$blk"
    [ "$t" = "MMC" ] && [ -n "$blk" ] && [ "$blk" != "$BOOTDEV" ] && EMMC="$blk"
done
[ -z "$EMMC" ] && EMMC=$(lsblk -dn -o NAME 2>/dev/null | grep '^mmcblk' | grep -v "^${BOOTDEV}$" | head -1)
say "eMMC alvo = ${EMMC:-<NENHUM>}"

if [ -z "$EMMC" ] || [ ! -b "/dev/$EMMC" ] || [ "$EMMC" = "$BOOTDEV" ]; then
    say "ERRO: eMMC nao encontrado/inseguro. ABORTADO."; set_led heartbeat; flush_to_card; exit 0
fi
SZ=$(cat /sys/class/block/$EMMC/size 2>/dev/null); say "tamanho eMMC = $((SZ/2048)) MB"
if [ "${SZ:-0}" -lt 2000000 ]; then say "ERRO: eMMC pequeno demais. ABORTADO."; set_led heartbeat; flush_to_card; exit 0; fi

IMG=$(ls /mnt/images/*.img.xz /mnt/images/*.img.gz /mnt/images/*.img 2>/dev/null | head -1)
say "imagem = ${IMG:-<NENHUMA>}"
[ -z "$IMG" ] && { say "ERRO: nenhuma imagem em /mnt/images."; set_led heartbeat; flush_to_card; exit 0; }

# Como o multitool (do_burn): le o Command Rate DDR do loader de fabrica ANTES de gravar,
# para regravar depois. Byte 16 antes da assinatura a7866565 nos 1os 128K: 0=1T, 1=2T.
CR_OFF=$(dd if="/dev/$EMMC" bs=128k count=1 2>/dev/null | od -A d -w4 -tx4 | grep -m1 a7866565 | cut -d' ' -f1)
CR_FAB=""; [ -n "$CR_OFF" ] && CR_FAB=$(od -A n -t u1 -j $((CR_OFF-16)) -N 1 "/dev/$EMMC" | tr -d ' ')
say "command rate de fabrica = ${CR_FAB:-<nao encontrado>} (0=1T 1=2T)"
dd if="/dev/$EMMC" bs=1M count=4 of=/mnt/emmc-fabrica-4MB.bin 2>/dev/null && say "backup dos 1os 4MB do eMMC em MULTITOOL/emmc-fabrica-4MB.bin"

printf '\n>>> GRAVANDO Armbian no /dev/%s. NAO DESLIGUE! (3-5 min)\n' "$EMMC" > "$TTY" 2>/dev/null
say ">> GRAVANDO $IMG em /dev/$EMMC (NAO DESLIGUE, 3-5 min)..."
set_led timer
case "$IMG" in
    *.xz) xz -dc "$IMG" | dd of="/dev/$EMMC" bs=512K iflag=fullblock oflag=direct ;;
    *.gz) gzip -dc "$IMG" | dd of="/dev/$EMMC" bs=512K iflag=fullblock oflag=direct ;;
    *)    dd if="$IMG" of="/dev/$EMMC" bs=512K iflag=fullblock oflag=direct ;;
esac
R=${PIPESTATUS[1]:-$?}
sync
say ">> dd terminou, exit=$R"
partprobe "/dev/$EMMC" 2>/dev/null; blockdev --rereadpt "/dev/$EMMC" 2>/dev/null; sleep 2
OFF=$(dd if="/dev/$EMMC" bs=128k count=1 2>/dev/null | od -A d -w4 -tx4 | grep -m1 a7866565 | cut -d' ' -f1)
say "assinatura DDR a7866565 offset=${OFF:-nao-encontrada}"
if [ -n "$OFF" ] && [[ "$CR_FAB" =~ ^[01]$ ]]; then
    printf "\\x0$CR_FAB" | dd of="/dev/$EMMC" bs=1 seek=$((OFF-16)) count=1 conv=notrunc 2>/dev/null; sync
    say "command rate regravado com o de fabrica: $(od -A n -t u1 -j $((OFF-16)) -N 1 /dev/$EMMC | tr -d ' ')"
fi

if [ "$R" -eq 0 ]; then
    say ">> aplicando led-conf7 (HDMI R29) no Armbian do eMMC..."
    mkdir -p /tmp/er; APPLIED=0
    for part in ${EMMC}p1 ${EMMC}p2 ${EMMC}p3; do
        [ -b "/dev/$part" ] || continue
        mount "/dev/$part" /tmp/er 2>/dev/null || continue
        ENV=""
        [ -f /tmp/er/boot/armbianEnv.txt ] && ENV=/tmp/er/boot/armbianEnv.txt
        [ -f /tmp/er/armbianEnv.txt ] && ENV=/tmp/er/armbianEnv.txt
        if [ -n "$ENV" ]; then
            grep -q '^overlays=' "$ENV" && sed -i 's/^overlays=.*/overlays=emmc led-conf7/' "$ENV" || echo 'overlays=emmc led-conf7' >> "$ENV"
            sync; say ">> led-conf7 aplicado em /dev/$part:$ENV -> $(grep '^overlays=' "$ENV")"
            APPLIED=1; umount /tmp/er; break
        fi
        umount /tmp/er 2>/dev/null
    done
    [ "$APPLIED" -eq 0 ] && say ">> AVISO: armbianEnv.txt nao encontrado no eMMC (HDMI do Armbian pode ficar preto)"
    printf '\n\n>>> SUCESSO! Desligue, TIRE O SD e ligue. (LED aceso fixo)\n\n' > "$TTY" 2>/dev/null
    say ">> SUCESSO! Armbian + led-conf7 no eMMC. Desligue, tire o SD e ligue."
    set_led default-on
else
    printf '\n\n>>> FALHA na gravacao (exit=%s). Veja autoflash.log no cartao.\n' "$R" > "$TTY" 2>/dev/null
    say ">> FALHA no dd (exit=$R)."; set_led heartbeat
fi
flush_to_card
umount /mnt 2>/dev/null
say "=== FIM ==="
