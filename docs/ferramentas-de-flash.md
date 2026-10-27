# rk322x-flash — reverse das ferramentas de flash RK3228A (14/10/2026)

Objetivo: decompilar todas as ferramentas que estavam em `~/Downloads` para gravar Armbian numa
placa **RK3228A**, entender por que nenhuma funcionou e juntar tudo numa ferramenta só.

Nada foi executado. Análise estática com REA 6.4.0 + Ghidra 12.1.4 (headless) e leitura dos logs.

## Por que não funcionou (dos logs de 05/05/2026)

Logs em `original/RKDevTool_Release_v2.86/.../Log/` e `original/RKDevTool_Release_v2.96_zh/.../Log/`.

| # | Sintoma no log | Causa | Evidência |
|---|---|---|---|
| 1 | `CheckDownloadItem--> ...rk356x_spl_loader_ddr1056_v1.10.111.bin is not existed` | o `config.cfg` usado era de **outra pessoa e outro chip** (RK356x, usuário `xiexi`) | `config.cfg` da pasta Armbian e do 2.86 |
| 2 | `Loading firmware failed,err=-5` (2.86) | o `update.img` era a **imagem Armbian crua renomeada** (sha256 idêntico ao `.img.xz` descompactado), não um firmware `RKFW` | hash conferido; o valor exato do `-5` não foi localizado no código (inferência) |
| 3 | `Start position of Image is larger than flash,start=0x40000000,flash=0x00E40000` (11×) | endereço de gravação herdado do config RK356x; o eMMC tem `0xE40000` setores (7296 MB) | log + `FUN_0040b330` do 2.96 |
| 4 | `GetDeviceStorage-->Storage op is not in the capability` (13×) | a **2.96** sempre tenta trocar a mídia antes de gravar (`CheckDeviceStorage`) e exige o bit `0x200` em `ReadCapability`; o loader RK322x não tem | `analise/RKDevTool_2.96/RKDevTool.exe.c`: `FUN_0041d410`, `FUN_0041d660`, chamadas de `FUN_0040b330`; a 2.86 não tem essa checagem automática |
| 5 | `Download multitool at 0x00000000...` → `RunProc is ending, ret=1` (03:45) | última tentativa: loader certo (`rk322x_loader_v1.10.256.bin`) + `multitool.img` no LBA 0 | se `ret=1` é sucesso não foi possível ler no pseudocódigo (argumento perdido) |

O que **funcionou** em todas as 24 tentativas: maskrom detectado, eMMC Samsung 7296 MB lido
(`FlashInfo: 00 00 E4 00 00 04 04 00 28 00 01`), loader enviado (`Download IDB Success`). O hardware
e o driver estão bons; o problema era configuração e versão da ferramenta.

## O que cada ferramenta é

| Ferramenta | Tipo | O que faz | Útil para a ferramenta única? |
|---|---|---|---|
| RKDevTool 2.86 / 2.96 | MFC x86, nativo | GUI oficial Rockchip: maskrom → loader → grava imagens/partições, upgrade de `update.img`, apagar, ler chip/flash | sim: fluxo e mensagens; 2.96 tem a troca de mídia que quebra no RK322x |
| AFPTool / RKImageMaker (2 versões cada) | nativo | empacotam/desempacotam `update.img` (`RKAF` dentro de `RKFW`) | só se quiser suportar `update.img` |
| DriverAssitant 5.14 | nativo + drivers | instala `rockusb.sys` (VID `2207`, PID `320B` = RK322x) e driver ADB | necessário só para o caminho rockusb.sys |
| rkDumper 1.1.1.0 | nativo (MinGW) | backup do eMMC por Rockusb, separando partições por assinatura | sim: backup antes de gravar |
| rkdeveloptool (fonte C++) | código aberto | CLI Linux/libusb da Rockchip: `db`, `ul`, `wl`, `rd`, `ef`… | **base principal**: protocolo completo em fonte |
| multitool-rk322x | imagem de SD (512 MB) | Linux de manutenção do paolosabatino: grava Armbian no eMMC a partir do cartão SD | caminho alternativo sem PC |
| loaders `.bin` | firmware | DDR init (471) + usbplug (472) + FlashData/FlashBoot | sim: **usar `rk322x_loader_v1.10.256.bin`** |
| rufus 4.14 | nativo, GPL | grava imagem em cartão SD | fonte público; não decompilado |

### Loaders (`analise/scripts/rk_loader_info.py`)

| Arquivo | Chip | Versão | Data | Observação |
|---|---|---|---|---|
| `rk322x_loader_v1.10.256.bin` | `322A` | 2.56 | 2020-01-21 | o mais novo; o que o Armbian recomenda |
| `RK3229MiniLoaderAll_V2.54.bin` | `322A` | 2.54 | 2019-04-18 | ok |
| `RK322XMiniLoaderAll_V2.32.bin` | `322A` | 2.32 | 2017-05-18 | ok, antigo |
| `RK32xxLoader(L)_uboot_V2.15_replace_ddr.bin` | outro (RK3288) | 1.25 | 2014-10-08 | **não usar** no RK3228A |

### multitool

As duas cópias (`original/soltos/multitool.img` e `original/multitool-rk322x/multitool.img`) têm
tabelas de partição diferentes (versões/estados distintos). Ambas têm o IDB cifrado no setor 64
(`3b8cdcfc…`), ou seja, dão boot sozinhas do SD ou do eMMC.

## Protocolo (base para a ferramenta única)

Fonte: `original/rkdeveloptool-master/rkdeveloptool/` (RKComm.h, RKDevice.cpp, main.cpp), confirmado
pelos nomes `RKU_*` no RKDevTool.

1. **Maskrom** (VID `0x2207`, PID `0x320B`): enviar o loader por *control transfer* vendor
   `0x0471` (DDR, entrada 471) e depois `0x0472` (usbplug, entrada 472), cifrados com RC4 quando
   `rc4Flag == 0` (nos loaders RK322x é 1 = sem RC4), respeitando `dataDelay`.
2. O usbplug reenumera como **Rockusb**; comandos por bulk em CBW de 31 bytes (`USBC`):
   `TEST_UNIT_READY 0x00`, `READ_FLASH_INFO 0x1A`, `READ_CHIP_INFO 0x1B`, `READ_LBA 0x14`,
   `WRITE_LBA 0x15`, `ERASE_LBA 0x25`, `READ_CAPABILITY 0xAA`, `CHANGE_STORAGE 0x2A`,
   `DEVICE_RESET 0xFF`.
3. Gravar a imagem crua do Armbian em **LBA 0** com `WRITE_LBA` em blocos, ler de volta para
   conferir, `DEVICE_RESET`.
4. **Não** chamar `CHANGE_STORAGE`/`READ_STORAGE` no RK322x (falha 4 acima).

Equivalente com o rkdeveloptool: `rkdeveloptool db rk322x_loader_v1.10.256.bin` →
`rkdeveloptool wl 0 Armbian…img` → `rkdeveloptool rd`. No Windows ele precisa de driver WinUSB
(libusb), não do `rockusb.sys`.

## Imagem Armbian

As imagens antigas (26.2.0-trunk.821, kernel 6.18.26, e a cópia renomeada para `update.img`) foram
apagadas em 14/10/2026. A atual, baixada do GitHub `armbian/community` (release mais recente):

| Arquivo | Publicada | Tamanho | sha256 |
|---|---|---|---|
| `imagens/Armbian_community_26.11.0-trunk.83_Rk322x-box_trixie_current_6.18.55_minimal.img.xz` | 2026-10-08 | 318484056 (1352 MiB descompactada) | `d2eefac6…e1e4e8` |

A release não publica hash; a integridade foi conferida pelo tamanho da API e por `xz -t`.
Também existe a variante `resolute … xfce_desktop` (807 MB) na mesma release.
Gravar a imagem **descompactada** (`.img`) em LBA 0, sem renomear para `update.img`.

## Descompilado (Ghidra headless, todas as funções, 0 falhas)

| Arquivo | Funções | Tamanho |
|---|---|---|
| `analise/RKDevTool_2.96/RKDevTool.exe.c` | 6609 | 6.4M |
| `analise/RKDevTool_2.96/AFPTool.exe.c` | 4954 | 5.1M |
| `analise/RKDevTool_2.96/RKImageMaker.exe.c` | 4922 | 4.9M |
| `analise/RKDevTool_2.86/RKDevTool.exe.c` | 6421 | 6.3M |
| `analise/RKDevTool_2.86/AFPTool.exe.c` | 1486 | 1.4M |
| `analise/RKDevTool_2.86/RKImageMaker.exe.c` | 1865 | 1.8M |
| `analise/DriverAssitant_5.14/DriverInstall.exe.c` | 3540 | 3.4M |
| `analise/DriverAssitant_5.14/RKDrvPreinst_x64.exe.c` | 1228 | 1.2M |
| `analise/DriverAssitant_5.14/rockusb_x64_win10/rockusb.sys.c` | 82 | 100K |
| `analise/DriverAssitant_5.14/rockusb_x64_win7/rockusb.sys.c` | 82 | 100K |
| `analise/rkDumper/rkDumper.exe.c` | 132 | 428K |

Boa parte das funções dos executáveis MFC é biblioteca (MFC/CRT linkadas estaticamente); as da
Rockchip são as que usam as mensagens `RKU_*`, `RKA_*`, `Layer<%s>`.

## Pastas

```
rk322x-flash/
├─ original/                 tudo como estava em Downloads (inclusive logs e configs das tentativas)
│  ├─ RKDevTool_Release_v2.86/  RKDevTool_Release_v2.96_zh/  DriverAssitant_v5.14/
│  ├─ rkDumper_1.1.1.0/  rkdeveloptool-master/  multitool-rk322x/
│  └─ soltos/                 multitool.img, .xz, rufus, rars, loaders/ (extraídos)
├─ imagens/                  Armbian a gravar (ver abaixo)
├─ analise/
│  ├─ <ferramenta>/<binario>.c            pseudocódigo Ghidra de TODAS as funções
│  ├─ <ferramenta>/<binario>.funcoes.tsv  endereço, nome, tamanho, strings usadas por função
│  ├─ <ferramenta>/<binario>.strings.tsv  strings e quais funções as usam
│  ├─ ghidra_scripts/ExportarTudo.java + exportar_todos.sh   (reproduz a exportação)
│  ├─ scripts/rk_loader_info.py           leitor do cabeçalho BOOT dos loaders
│  └─ snapshots/                          evidências do REA
└─ README.md
```

Para achar uma função: procure a mensagem de log em `*.strings.tsv` (coluna 2 = funções que a
usam) e depois `// ==== FUN_<endereço>` no `.c`.

## Limites

- Pseudocódigo Ghidra: nomes `FUN_xxxx`, sem tipos MFC; não é o fonte original.
- Não decompilados: adb/AdbWin*.dll (Google, fonte aberto), DIFxAPI e coinstallers WDF
  (Microsoft), rufus (GPL, fonte público), loaders (firmware ARM, só o cabeçalho foi lido).
- Nenhuma execução nem teste com a placa.
