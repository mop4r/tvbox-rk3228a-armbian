# Instalar / reinstalar o Armbian na box (do zero)

Material: repositório privado **https://github.com/mop4r/tvbox-rk3228a-armbian** (imagens e backups nas Releases `instalacao-2026-10-14` e `backup-e-analise`); a pasta completa fica no PC de casa em `~/workspace/repos/rk322x-flash/`
- `original/soltos/multitool-rk322x.xz` — **a base que boota nesta placa** (sha256 `8964182ebbccab55686766bf7b5a0f6a290f3e5a73df85e05fb1c0b5f385c5fc`)
- `original/soltos/multitool.img` — **NÃO usar** (sha256 `29dac19a…`): outra build, não boota aqui. Perdi horas modificando a base errada.
- `imagens/Armbian_community_26.11.0-trunk.83_Rk322x-box_trixie_current_6.18.55_minimal.img.xz` (release mais recente em 08/10/2026; achar novas pela API `repos/armbian/community/releases`, asset com `Rk322x-box`)
- `analise/multitool/multitool-FINAL.img` — SD auto-instalador já montado (**autoflash antigo**, sem preservar Command Rate; para reconstruir use `ferramentas/autoflash.sh`; na Release é `multitool-autoinstalador.img.xz`)
- `original/soltos/loaders/rk322x_loader_v1.10.256.bin` (loader certo; o `RK32xxLoader V2.15` é de outro chip)

## Por que as ferramentas de PC falharam (não repetir)
Logs do RKDevTool de 05/05/2026: `config.cfg` de RK356x (de outro usuário), Armbian cru **renomeado para `update.img`**, endereço `0x40000000` (maior que o eMMC), e o **RKDevTool 2.96 exige troca de mídia** que o loader RK322x não tem ("Storage op is not in the capability"). E o maskrom nunca enumerou nesta placa (ver `hardware.md`). **Caminho que funciona: SD auto-instalador.**

## 1. Montar o SD auto-instalador (WSL Ubuntu-24.04)
Partições da base (MBR, disk id `0x824f9f97`): p1 NTFS `MULTITOOL` (setor 301248, imagens vão em `images/`), p2 FAT boot (170176: `kernel.img`, `rk322x-box.dtb`, `extlinux/extlinux.conf`), p3 **squashfs gzip, bloco 131072** (32768, 137408 setores = rootfs).

Mudanças (é o que existe na `multitool-FINAL.img`):
1. `/sbin/init` (script próprio do multitool, não systemd): depois do `ifconfig eth0 up` → `/sbin/ifconfig eth0:2 192.168.0.250 netmask 255.255.255.0`; antes do menu → `bash /usr/local/bin/autoflash.sh <> /dev/tty1 >&0 2>&1`. (O init original já sobe DHCP, link-local `169.254.120.120` e dropbear `-B` com **root sem senha**.)
2. `/usr/local/bin/autoflash.sh` = `ferramentas/autoflash.sh`: acha o eMMC (tipo MMC ≠ disco do boot), lê o Command Rate e faz backup de 4 MB **antes**, grava `xz -dc img | dd of=/dev/mmcblkX bs=512K oflag=direct`, regrava o Command Rate de fábrica, aplica `overlays=emmc led-conf7` no `armbianEnv.txt`, sinaliza LED e loga tudo em `MULTITOOL/autoflash.log`.
3. `extlinux.conf` da p2: acrescentar `console=tty1` (texto do kernel no HDMI).
4. Reconstruir o squashfs: `sudo unsquashfs` → editar → `sudo mksquashfs ... -comp gzip -b 131072 -noappend`. **Sempre gzip** (zstd/xz o kernel do multitool não monta) e **sempre com sudo** (sem root ele zera `/etc/shadow` e as chaves do dropbear). Se não couber, apagar `/usr/share/{doc,man,info}` e caches do apt (seguro). Gravar o squashfs na p3 por cima (`dd ... conv=notrunc`).

## 2. Gravar o SD pelo Windows (jeito confiável)
- Identificar o cartão: `Get-Disk` → o único `BusType USB` de ~7,4 GB (no PC de casa = **disco 4 = `/dev/sde` no Git Bash**; o C: é `/dev/sdd`). **Conferir tamanho antes de qualquer `dd`.**
- O **WSL não aceita esse leitor** (`wsl --mount` dá 0x8007000f); gravar pelo **Git Bash**.
- Sequência: `diskpart` com script em arquivo (`select disk N` / `clean`) → `mountvol /N` (desliga automount; senão o Windows monta partições no meio e dá *Permission denied*) → `dd if=img of=/dev/sdX bs=1M conv=fsync`.
- O hash do cartão inteiro **sempre difere** (Windows mexe em metadados FAT/NTFS); verificar **no nível de arquivo** (montar o squashfs, ler o `init`/`extlinux.conf`).
- Copiar o `.img.xz` do Armbian para `MULTITOOL:\images\`.
- **No fim: `mountvol /E` e confirmar "Montagem automática de novos volumes ativada"** — Pedro exige automount ligado (pen drives sem letra é inaceitável).
- O leitor às vezes some no meio ("No medium found"); é o leitor, o cartão está saudável. Regravar.

## 3. Instalar na box
1. SD na box, cabo de rede, TV na entrada HDMI certa, ligar.
2. ~60 s em `Waiting for root device ...` (SD por USB = `sda`) — **normal**.
3. Tela mostra `AUTO-FLASH`, `eMMC alvo = mmcblk2`, `GRAVANDO ... NAO DESLIGUE`. A chuva de `rockchip-vop ... POST_BUF_EMPTY irq err` e `dwmmc_rockchip: Unexpected interrupt latency` é **inofensiva** (vídeo/eMMC sob carga do kernel 4.4).
4. **Leva ~21 min**, não 3–5. Dá para acompanhar por `plink -pw "" root@192.168.0.250` (SSH fica lento durante a gravação; não insistir).
5. Fim: `>>> SUCESSO`, LED fixo. Depois o init abre o menu do multitool (dialog com LICENSE) — normal.
6. Desligar (pelo menu ou tomada), **tirar o SD**, ligar.

## 4. Primeiros boots do Armbian
- Pega IP por **DHCP** no primeiro boot (era `192.168.0.154`); depois fixar em `192.168.0.4` com o `etc/netplan/10-dhcp-all-interfaces.yaml` do kit (usar retorno automático: `systemd-run --on-active=180` restaurando o backup, e cancelar o timer depois de entrar pelo IP novo). `root`/`1234` até o primeiro login.
- O `armbian-firstrun` **regenera as chaves SSH no segundo boot** → host key muda de novo; aceitar depois de conferir o MAC `2e-ea-8d-b7-30-0f`.
- **Tela preta com HDMI "connected" = 4K do EDID**: pôr `video=HDMI-A-1:1920x1080@60` no `extraargs` do `/boot/armbianEnv.txt` e reiniciar.
- Depois: refazer a configuração de `servicos.md` usando os arquivos de `arquivos-da-box/` (mesmos caminhos da raiz da box).

## 5. Ordem para reconfigurar tudo
1. Usuário `mopar` (sudo), senha de root trocada, `rm /root/.not_logged_in_yet`, fuso `America/Sao_Paulo`.
2. `apt-mark hold` em `linux-u-boot-*`, `linux-image-*`, `linux-dtb-*` **antes** do primeiro upgrade (o full-upgrade traz os três).
3. `apt full-upgrade` + `unattended-upgrades` (`etc/apt/apt.conf.d/*`).
4. Proteções: watchdog, ramoops (`armbian-add-overlay ramoops.dts`), sysctls, journal persistente, ramlog desligado, `blackbox`, `diagnostico`.
5. `ddr-turbo` + timer de confirmação + `blacklist rk3228_dmc` + `update-initramfs -u` + overlay `ddr3-660`; `ddr-turbo armar 660`; reboot limpo.
6. Unbound (precisa `dns-root-data` + `unbound-anchor`) → Pi-hole (instalação `--unattended`) → listas → crons → `dnsguard` → Tailscale.
7. Rodar o teste de exaustão (`/opt/netlab/stress.sh 40 <rotulo>` + PC puxando o blob) antes de confiar.
