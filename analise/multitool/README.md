# Multitool (Paolo Sabatino / jock) — análise (14/10/2026)

Origem: `original/multitool-rk322x/multitool.img` (imagem de cartão SD, 512 MB). Não é um `.exe` —
é um Linux de resgate. "Decompilar" aqui = extrair o sistema de arquivos e ler os scripts.
Montado via WSL (loop), `multitool.sh` copiado para esta pasta (1229 linhas, bash comentado).

## Estrutura da imagem (3 partições)

| Part | Tipo | Conteúdo |
|---|---|---|
| p1 | NTFS 365 MB (label `MULTITOOL`) | pasta `images/` (você põe o Armbian aqui) + `bsp/` (u-boot p/ NAND) |
| p2 | FAT32 64 MB (boot) | kernel + DTB + u-boot que dá boot no multitool |
| p3 | ext 67 MB | rootfs: `/usr/local/bin/multitool.sh` (o menu/gravador) |

## O coração: `multitool.sh` → `do_burn()` (gravação no eMMC)

É o que grava o Armbian no armazenamento interno. O algoritmo, para **eMMC** (caso do RK3228A):

```bash
# 1. acha os eMMC em /sys/bus/mmc/devices (type=MMC) → normalmente mmcblk2
# 2. monta a partição MULTITOOL, lista images/
# 3. detecta o formato (7z/zip/xz/gz/img) → monta D_COMMAND_LINE (pipe de descompressão)
# 4. GRAVA, cru, a partir do setor 0:
<descompacta a imagem> | dd of=/dev/mmcblkX skip=0 seek=0 bs=512K iflag=fullblock oflag=direct
# 5. (rk322x) ajusta o Command Rate do DDR — ver abaixo
```

**É só isso.** Para eMMC, gravar a imagem Armbian **crua, descompactada, no bloco `/dev/mmcblkX`
a partir do offset 0.** A imagem já carrega idbloader + u-boot + partições. Confirma o que o
`repos/rk322x-flash/README.md` dizia (gravar em LBA 0, não renomear para update.img).

### Caso especial NAND (`rknand0`) — não é o nosso

Se o bloco for `rknand*` (driver proprietário), o driver não escreve o idbloader. O script:
pergunta se pula os primeiros `0x2000` setores (8 blocos de 512K), grava o resto, restaura a
tabela de partição (primeiros 64 setores) e escreve um u-boot legado (`bsp/legacy-uboot.img` em
seek=1 bs=4M). O fórum (jock, 2025/26) recomenda **abandonar NAND** e usar eMMC/SD mainline.

## Específico do rk322x: Command Rate do DDR (`get/set_command_rate`)

Só o `TARGET_CONF = rk322x` mexe nisso. Depois de gravar, lê o Command Rate (1T/2T) do DDR:
- acha a assinatura `a7866565` nos primeiros 128 KB da imagem;
- o byte do Command Rate fica **16 bytes antes** da assinatura (`0x00`=1T, `0x01`=2T);
- reescreve esse byte no device para casar a temporização certa (DDR "exigente" só boota em 1T ou 2T).

Essa é a armadilha "DDR instável / não boota" que o fórum cita. Uma ferramenta nossa precisa
reproduzir isso para RK3228A.

## `do_install_jump_start()` — pôr Armbian para bootar em box com NAND

Grava u-boot e TEE na NAND (offsets `0x2000` e `0x6000`), copiando do dispositivo de boot do SD.
Permite um box de NAND dar boot por SD/USB sem apagar a NAND. Só para o caminho NAND.

## Outras funções (menu)

`do_backup`/`do_restore` (backup da flash), `do_erase_mmc` (apaga eMMC — útil para forçar boot
por SD), `do_install_stepnand` (u-boot legado na NAND), `do_change_command_rate`, `do_give_shell`,
`do_reboot`, `do_shutdown`. Descompressão em `get_decompression_cli` (7z/zip/xz/gz).

## Para a nossa ferramenta (recriar do zero)

O multitool roda **dentro do box** (Linux no SD). Nossa ferramenta roda **no PC**, pelo USB
(maskrom/rockusb). Mas a lógica de gravação é a mesma ideia — escrever a imagem crua no bloco a
partir do 0. Pelo PC, o equivalente ao `dd of=/dev/mmcblk` é o `rkdeveloptool`:

```
rkdeveloptool db rk322x_loader_v1.10.256.bin      # sobe o loader (DDR+usbplug) por maskrom
rkdeveloptool wl 0x0 Armbian_...img               # write LBA: grava a imagem crua a partir do setor 0
rkdeveloptool rd                                   # reinicia
```

O multitool confirma o essencial: **gravar a imagem crua a partir do setor 0** e, no rk322x,
**acertar o Command Rate do DDR**. Esses são os dois pontos que a ferramenta do PC precisa acertar.
