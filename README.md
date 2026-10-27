# TV box RK3228A com Armbian: servidor Pi-hole da casa

TV box genérica **MXQ PRO "5G"** (placa **R29_5G_LP3 V3.0**, SoC Rockchip **RK3228A**, 1 GB LPDDR3, eMMC de
7,3 GB) transformada em servidor da casa com **Armbian 26.11 (Debian Trixie, kernel 6.18)** no eMMC:

- **Pi-hole v6 + Unbound** (DNS por TLS para Quad9/Cloudflare), DNS da casa toda e da tailnet do Tailscale
- **chrony**: servidor de hora da casa (NTP.br)
- **DDR a 660 MHz** com volta automática para 330 se não aguentar (`ddr-turbo`)
- caixa-preta, watchdog e despejo de pânico para descobrir por que caiu (`blackbox`, `diagnostico`, ramoops)
- monitor de latência da internet por hora (`netmon`), Uptime Kuma, painel da rede (repositório à parte)

Tudo foi descoberto e testado nesta placa. Ela tem armadilhas que não são óbvias: leia
[`docs/hardware.md`](docs/hardware.md) antes de mexer.

> *English summary:* Armbian 26.11 (Debian Trixie, kernel 6.18) installed on the eMMC of a generic
> **MXQ Pro 4K "5G" TV box** with the **R29_5G_LP3 V3.0** board and a **Rockchip RK3228A** SoC, running as a home
> **Pi-hole + Unbound (DNS over TLS) + Tailscale** server. Includes: an SD-card auto-installer built from
> the rk322x multitool (writes Armbian to eMMC by itself, no maskrom needed), the fix for the **black HDMI screen**
> on R29 boards (4K EDID → force `video=HDMI-A-1:1920x1080@60`), permanent **DDR 660 MHz** with automatic
> fallback, crash diagnostics (ramoops, watchdog, black box), and why RKDevTool failed on this board.

## Estado (27/10/2026)

| Item | Valor |
|---|---|
| Acesso | `mopar@192.168.0.4` (LAN, IP fixo) ou pelo Tailscale (`pihole-box`) |
| Sistema | Armbian community 26.11.0-trunk.83, Trixie, kernel 6.18.55 (kernel, dtb e u-boot em `apt-mark hold`) |
| DNS | Pi-hole + Unbound DoT, ~841 mil domínios, firewall `dnsguard` na porta 53 |
| Memória | DDR 660 MHz permanente (`ddr-turbo`) |
| Pendente | instabilidade de memória em transiente de energia (suspeita de capacitores faltando sob o SoC); Wi-Fi BCM4330 morto (usar adaptador USB) |

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [`docs/instalacao.md`](docs/instalacao.md) | **Reinstalar do zero**: SD auto-instalador, gravar o SD no Windows, primeiros boots, ordem de reconfiguração |
| [`docs/hardware.md`](docs/hardware.md) | placa, chips, LEDs, SD por ponte USB, HDMI 4K, DDR, pinos de fábrica, Wi-Fi, benchmarks, o GPIO que desliga a placa |
| [`docs/servicos.md`](docs/servicos.md) | Pi-hole, Unbound, listas, firewall, Tailscale, roteador da Claro, atualizações, `ddr-turbo`, proteções, rede |
| [`docs/historia.md`](docs/historia.md) | linha do tempo da instalação, com os becos sem saída |
| [`docs/ferramentas-de-flash.md`](docs/ferramentas-de-flash.md) | por que o RKDevTool falhou; protocolo maskrom/Rockusb; o que cada ferramenta é |
| [`docs/multitool.md`](docs/multitool.md) | como o multitool grava o eMMC e acerta o Command Rate da DDR |
| [`docs/guia-do-forum.md`](docs/guia-do-forum.md) | resumo do tópico do fórum Armbian e os dois caminhos (SD e maskrom) |

## Pastas

```
arquivos-da-box/   cópia fiel dos scripts e configs da box (restaurar no mesmo caminho a partir da raiz /)
ferramentas/       autoflash.sh (instalador do SD), carve_dtb.py (DTB de ROM Android),
                   instalar-uptime-kuma.sh, espelhar-skill.sh
scripts/box.sh     roda script/comando na box como root, pelo plink (lê o acesso de um .env fora do git)
analise/           multitool.sh lido, DTB/DTS de fábrica, leitor de loader, scripts do Ghidra, evidências REA
docs/              documentação acima
```

`arquivos-da-box/`, `ferramentas/`, `scripts/box.sh` e `docs/{hardware,instalacao,servicos}.md` são espelho
da skill `tvbox-rk3228a` do Claude (`ferramentas/espelhar-skill.sh` copia de lá).

## Releases (binários fora do git)

| Release | Arquivos |
|---|---|
| `instalacao-2026-10-14` | `multitool-autoinstalador.img.xz` (SD pronto que grava o Armbian sozinho), `multitool-rk322x-base.img.xz` (base que boota nesta placa), imagem Armbian usada, `rk322x_loader_v1.10.256.bin`, `SHA256SUMS` |
| `backup-e-analise` | `R29_5G_LP3_V1.2_00523.img.xz` (ROM Android de fábrica da placa V1.2, fonte do device tree), `ferramentas-originais.tar.xz` (RKDevTool 2.86/2.96, DriverAssistant, rkDumper, rkdeveloptool, loaders, logs de 05/05), `analise-descompilacao.tar.xz` (pseudocódigo Ghidra de todas as funções), `multitool-intermediarios.tar.xz` |

O `multitool-autoinstalador` tem a primeira versão do `autoflash.sh` (não preserva o Command Rate de
fábrica). Para gerar um novo com a versão atual, ver `docs/instalacao.md`, passo 1.

## Instalar em 4 passos (resumo)

1. Gravar `multitool-autoinstalador.img` num microSD (no Windows: `diskpart clean` + `dd`, ver `docs/instalacao.md`).
2. Copiar a imagem do Armbian (`.img.xz`) para a pasta `images/` da partição `MULTITOOL`.
3. SD na box, cabo de rede, ligar. Esperar ~60 s em `Waiting for root device` (normal) e ~21 min de gravação
   até `>>> SUCESSO` e LED fixo.
4. Tirar o SD, ligar. Se o HDMI ficar preto: `video=HDMI-A-1:1920x1080@60` no `extraargs` do
   `/boot/armbianEnv.txt`. Depois restaurar `arquivos-da-box/` na ordem de `docs/instalacao.md`, passo 5.

## Nunca fazer

- Acionar **GPIO0_D6** (`gpiochip0` linha 30): corta a energia da placa.
- Tirar kernel/dtb/u-boot do `hold` sem o procedimento manual de `docs/servicos.md`.
- Mudar a frequência da DDR fora do `ddr-turbo`.
- Usar o `sbc-bench.sh` original (publica os resultados no 0x0.st).

## Licença

Scripts e documentação: GPL-2.0 (o `multitool.sh` é de Paolo Sabatino, GPL). Firmware, ROM e ferramentas
da Rockchip nas Releases pertencem aos seus donos e estão aqui só como backup.

## Palavras-chave / search keywords

RK3228A, RK3229, RK322x, Rockchip, TV box, MXQ Pro, MXQ Pro 4K 5G, MXQ 4K, R29, R29_5G_LP3, R29-5G-LP3,
R29_5G_LP3_V3.0, R29_5G_LP3_V1.2, R2B, H20, led-conf7, rk322x-config, multitool, rk322x multitool, Armbian
rk322x-box, Armbian CSC, eMMC install, SD card boot, maskrom, rkdeveloptool, RKDevTool, BCM4330, SWB-B42B,
LPDDR3, ddr3-660, rk3228_dmc, devfreq, Pi-hole, Unbound, DNS over TLS, Tailscale, home server, instalar Armbian
em TV box, tela preta HDMI, TV box servidor.

Mensagens de erro tratadas aqui: `Waiting for root device PARTUUID` (normal: o SD é USB nesta placa),
HDMI preto com "connected", `Storage op is not in the capability`, `Start position of Image is larger than flash`,
`Loading firmware failed,err=-5`, `POST_BUF_EMPTY irq err`, `Failed to initialize a non-removable card` (Wi-Fi),
`Unable to handle kernel paging request ... unmap_page_range`, "The versions file is incomplete" (Pi-hole).
