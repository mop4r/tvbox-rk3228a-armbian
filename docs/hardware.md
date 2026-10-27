# Hardware da TV box RK3228A (R29_5G_LP3 V3.0)

## Identidade

| Item | Valor |
|---|---|
| Placa (serigrafia) | `R29_5G_LP3_V3.0_231005`, etiqueta `hxw24051403-b 20240520(mls)` |
| Caixa / família | MXQ PRO 4K "5G" (genérica chinesa) |
| SoC | Rockchip **RK3228A** (marcação `SDDKX22033 2313`), 4× Cortex-A7, ARMv7 32 bits, sem extensão de cripto |
| RAM | Micron **LPDDR3** (FBGA `JZ099`, marca `8SA97`), 1 GB (970 MB visíveis) |
| eMMC | Samsung ~7,3 GB (7296 MB). No Armbian = `mmcblk2` |
| Rede | Ethernet **100 Mb/s** (PHY interno), interface `end0` |
| MAC | `2e:ea:8d:b7:30:0f` (gerado pelo Armbian a partir do serial do SoC; estável) |
| Wi-Fi/BT | módulo **SWB-B42B** (data `130311` = 2013) numa plaquinha verde adaptadora = módulo do **Samsung Galaxy S2**, chip **Broadcom BCM4330**. **Não funciona no Linux** (ver abaixo) |
| Dissipador | sobre o SoC; temperatura em carga máxima 64–66 °C (660 MHz), sem throttling |
| Portas | HDMI, 2× USB host, RJ45, AV, entrada 5 V, IR |

## LEDs
- **Vermelho fixo sozinho** = energizada, sem sistema rodando (normal antes de bootar ou eMMC sem sistema).
- **Âmbar/amarelo piscando ao lado do vermelho** = atividade, lendo o cartão SD (bootando).
- **Azul** = Armbian rodando (a overlay `led-conf7` controla os LEDs da R29).
- Durante o autoflash (`led:state1`): `timer` piscando = gravando; `default-on` fixo = sucesso; `heartbeat` = erro.

## Boot e armazenamento — fatos que enganam
- **O slot microSD é ligado por uma ponte USB interna.** No Linux o cartão aparece como **`sda`** (USB/SCSI), não `mmcblk0`, e a enumeração é lenta: o kernel fica **~58 s** mostrando `Waiting for root device PARTUUID=824f9f97-03` antes do `[sda] Attached SCSI removable disk`. **É normal, só esperar.** (Eu já culpei a assinatura de disco por isso; estava errado — ela estava certa.)
- **Maskrom pelo USB nunca funcionou** nesta placa (VID `2207`, PID `320b` nunca apareceu): o eMMC é BGA (sem pino de clock acessível para o curto) e o botão de reset não basta. **Caminho de instalação = cartão SD**, ver `instalacao.md`.
- O cartão SD tem prioridade quando o eMMC não tem sistema bootável; com Armbian no eMMC, ligar com o SD do multitool ainda boota pelo SD.

## Vídeo (HDMI)
- A TV do Pedro anuncia **4K** no EDID; o kernel 6.18 escolhe 3840x2160@60 (594 MHz), que o RK3228A não gera → **tela preta com HDMI "connected"**. Correção obrigatória: `extraargs=... video=HDMI-A-1:1920x1080@60` no `/boot/armbianEnv.txt`.
- No multitool, o console do kernel vai para a serial (ttyS2); para ver texto no HDMI é preciso `console=tty1` no `extlinux.conf` dele.
- A overlay `led-conf7` ("R29_MXQ, R2B_MXQ, H20" no `rk322x-config`) é a certa para esta placa (LEDs, reset, reguladores); não foi ela que consertou o HDMI.
- Já aconteceu de a TV estar na **entrada HDMI errada** — conferir antes de concluir "sem vídeo".

## CPU e memória
- CPU: 600 / 816 / 1008 MHz, todos a **1,2 V fixos** (tabela `cpu-opp-table-r29`, que entra pelo `led-conf7`). Não é subtensão.
- DDR: o loader (`DDR Version V1.11 20200910`) liga a memória em **330 MHz**. O registrador DPLL lê 660 porque o PLL é **2× a DDR** (não confundir). Degraus do `dmc`: 330 / 534 / 660 (786 desativado no DT).
- O driver `rk3228_dmc` (módulo) sobe a DDR em tempo de execução via SIP/TEE; reporta `LPDDR3`, `CL8-8-8-14`, `command rate 1T`. O byte de Command Rate no loader (16 bytes antes da assinatura `a7866565`) é `1` = 2T, igual no multitool e no Armbian — não é causa de nada.
- **Estado atual: 660 MHz permanente** via serviço `ddr-turbo` (ver `servicos.md`). 660 passou 40 min de exaustão sem erro.

## Instabilidade de memória (suspeita de hardware, em aberto)
Dois episódios de **corrupção de memória**, os dois em transiente de energia, nunca em carga contínua:
1. Durante um `speedtest-cli` (14/10 ~07:05, DDR 330): SSH/DNS mortos com ping vivo; depois os pacotes saíram com **MAC corrompido** (`b7-30` → `c9-30` → `59-41`) e a box parou.
2. Logo após um corte de energia (GPIO0_D6, 14/10 ~17:00, DDR 330): **loop de pânico no boot** — `Unable to handle kernel paging request ... PC is at unmap_page_range` no `udev-worker` aos 15 s.

Hipótese forte: **capacitores de desacoplamento atrás do SoC não soldados** (o usuário pocng achou isso numa R29_5G_LP3 V1.2; fórum LibreELEC fio 25236, post #631). Pendente: foto do **verso da placa sob o SoC** (pads vazios = confirmado). Por isso o DNS do roteador **ainda não** aponta para a box.

## Pinos (device tree de fábrica do Android)
Fonte: ROM `R29_5G_LP3_V1.2_00523` (pocng confirmou que a V3.0 usa os mesmos pinos de Wi-Fi). Extraído em `repos/rk322x-flash/analise/android-dtb/fabrica.dts` (PC de casa).

| Função | Pino | Observação |
|---|---|---|
| Energia do Wi-Fi (`WIFI,poweren_gpio`) | **GPIO2_D2** (gpio2 26), ativo alto | = `sdio-pwrseq` do Armbian (reset ACTIVE_LOW). **Polaridade original é a certa** |
| Wi-Fi acorda o SoC | GPIO0_D4 | entrada |
| Energia do Bluetooth (`BT,power_gpio`) | **GPIO2_D5** (gpio2 29), ativo alto | acionar é seguro (testado); não fez o Wi-Fi responder |
| BT wake / BT host wake | GPIO3_D3 / GPIO3_D2 | |
| SDIO (Wi-Fi) | GPIO3_A0 clk, A1 cmd, A2–A5 dados, função 1 | iguais no Armbian; pulls corretos |
| `sdio_vref` | 3,3 V | |
| **GPIO0_D6** (`sdio-pwren` da fábrica) | **NUNCA ACIONAR** | `gpioset gpiochip0 30=1` **cortou a energia da placa** (nem o watchdog reiniciou) e o boot seguinte entrou em loop de pânico |
| Reset (botão) | gpio3 25 | |
| LEDs | gpio1 7 (working), gpio3 21 (auxiliary) | |

## Wi-Fi / Bluetooth — estado (não resolvido)
- `brcmfmac` + `brcmfmac4330-sdio.bin`/nvram + `BCM4330B1.hcd` **já estão na box**; o chip simplesmente não responde no `mmc1` (`Failed to initialize a non-removable card`, em 400/300/200/100 kHz).
- Testado sem sucesso: as duas polaridades do GPIO2_D2, GPIO2_D5 ligado, rebind do `30010000.mmc`. A configuração de software já é igual à de fábrica.
- Suspeitas: falta o **clock LPO de 32 kHz** que o BCM4330 exige (nem a fábrica declara um; `xin32k_out` existe mas ninguém usa), ou módulo reaproveitado morto. Pedro diz que **funcionava no Android original**, mas a ROM original dele foi sobrescrita e não há cópia (o backup de 100 MB do pocng sumiu do servidor dele).
- **Solução recomendada: adaptador USB** — Wi-Fi com MediaTek **MT7601U** (2,4 GHz) ou **MT7610U/MT7612U** (5 GHz), driver `mt76`; Bluetooth **CSR8510 A10** ou **RTL8761B**. Conferir o chip real com `lsusb`.
- **Não fazer varredura de GPIO** sem o Pedro aceitar o risco explicitamente (já derrubamos a placa uma vez).

## Benchmarks (sbc-bench 0.9.72, kernel 6.18, CPU 1008 MHz)

| | 7-zip 4n | 7-zip 1n | AES | memcpy | memset | Pi-hole q/s |
|---|---|---|---|---|---|---|
| DDR 660 | **1960** | **588** | 19350 | **820** | **2170** | **~660** |
| DDR 330 | 1710 | 533 | 19090 | 370 | 1830 | ~455 |
| Raspberry Pi 2 B+ (ref.) | 2070 | 592 | 17450 | 615 | 1175 | — |
| Raspberry Pi 3 B (ref.) | 2970 | 977 | 36230 | 1110 | 1700 | — |

Em 660 a box ≈ Raspberry Pi 2. Logs completos em `/var/lib/bench/` na box. O `sbc-bench.sh` original **envia resultados ao 0x0.st**; usar `/opt/netlab/sbc-bench-local.sh` (cópia com upload removido).
