# Como chegamos aqui (linha do tempo)

Resumo das conversas em que a box foi instalada e configurada. O passo a passo para repetir está em
[`instalacao.md`](instalacao.md); aqui fica o caminho, com os becos sem saída, para não repetir.

## 05/05/2026: as tentativas que falharam

Antes do Claude, várias tentativas de gravar o Armbian pelo PC com o **RKDevTool** (2.86 e 2.96), o
DriverAssistant e um `config.cfg` baixado da internet. Todas falharam. Os logs ficaram nas pastas das
ferramentas (release `ferramentas-originais`). No meio dessas tentativas o eMMC perdeu o sistema de fábrica:
a box passou a acender só o LED vermelho.

## 14/10/2026, madrugada: engenharia reversa das ferramentas

1. Todas as ferramentas de flash da pasta Downloads foram descompiladas (REA + Ghidra headless, todas as
   funções) e guardadas aqui; os originais saíram de Downloads.
2. Diagnóstico pelos logs ([`ferramentas-de-flash.md`](ferramentas-de-flash.md)): `config.cfg` de outro chip
   (RK356x), Armbian cru renomeado para `update.img`, endereço de gravação maior que o eMMC, e o RKDevTool
   2.96 exige uma troca de mídia que o loader do RK322x não tem.
3. Pesquisa: tópico "CSC Armbian for RK322x TV box boards" do fórum Armbian (105 páginas) e o vídeo
   "Instalando Linux em TV Box com RK322X!" (legendas bloqueadas). Guia em [`guia-do-forum.md`](guia-do-forum.md).
4. O **multitool** (Paolo Sabatino / jock) foi aberto e lido: grava a imagem crua no eMMC a partir do setor 0
   e acerta o Command Rate da DDR ([`multitool.md`](multitool.md)).
5. Baixada a imagem mais nova: Armbian community 26.11.0-trunk.83, Trixie, kernel 6.18.55, minimal.

## 14/10, manhã: maskrom não deu, o SD deu

- A box ligada no USB **nunca apareceu** como `2207:320b` (maskrom). O eMMC é BGA, sem pino de clock
  acessível para o curto; segurar o reset não basta. A placa foi identificada pela serigrafia:
  **R29_5G_LP3 V3.0_231005**.
- Caminho escolhido: **cartão SD**. Como o eMMC estava sem sistema (LED só vermelho), o SoC cai no SD sozinho.
- Primeira tentativa: Armbian direto no SD. O LED âmbar piscou muito tempo e o HDMI ficou preto.
- Segunda: só o multitool no SD. Bootou, mas tela preta e sem SSH conhecido.
- **Multitool modificado** (pedido do Pedro: "que toda instalação direto na memória seja feita por SSH"):
  IP fixo `192.168.0.250` + `autoflash.sh` que grava sozinho ao ligar. As primeiras versões foram feitas
  sobre a base errada (`soltos/multitool.img`, outra build, que não boota nesta placa) e com squashfs
  sem gzip/sem sudo; horas perdidas. Base certa: `soltos/multitool-rk322x.xz`.
- `console=tty1` no `extlinux.conf` do multitool fez o HDMI mostrar texto pela primeira vez (o console ia
  para a serial).
- Descoberta que custou caro: **o slot microSD é ligado por uma ponte USB interna**. O cartão vira `sda`
  e o kernel fica ~58 s em `Waiting for root device`. Parecia travado; era só esperar.
- Também: a TV estava na **entrada HDMI errada** numa das tentativas.
- Gravação no eMMC: **~21 min** (não 3–5), `dd` sem erro, terminou às 09:10 UTC.

## 14/10, manhã: primeiro boot do Armbian

- LED azul, mas HDMI preto. Causa: a TV anuncia **4K no EDID**, o kernel 6.18 escolhe 3840x2160@60, que o
  RK3228A não gera. Correção: `video=HDMI-A-1:1920x1080@60` no `extraargs` do `armbianEnv.txt`.
- Usuário `mopar`, root com a mesma senha, fuso de São Paulo, `apt-mark hold` em kernel/dtb/u-boot antes
  do `full-upgrade`, `unattended-upgrades`.
- Pi-hole v6 + Unbound. Benchmark de três modos do Unbound: DoT (Quad9 + Cloudflare) venceu o recursivo
  próprio. Listas StevenBlack + HaGeZi pro + TIF (841 mil domínios).

## 14/10, ~07:05: o primeiro travamento

Durante um `speedtest-cli` a box parou de responder (ping vivo, SSH/DNS mortos) e depois mandou pacotes com
**MAC corrompido**. Daí nasceram as proteções: watchdog, ramoops, `kernel.panic=10`, journal persistente,
`blackbox` (a cada 30 s) e o comando `diagnostico`. Cadeia testada com `sysrq-c`.

## 14/10, tarde: DDR

- Descoberto que, sem driver, a DDR roda em **330 MHz** (o mínimo); o PLL lê 660 porque é 2× a DDR (eu li
  errado e disse 660 ao Pedro; corrigido). 330 passou 20 min de stress.
- Pedro pediu o máximo (660), com volta automática se não subir. Nasceu o **`ddr-turbo`**: carrega o
  `rk3228_dmc` depois do boot, fixa 660 e desarma sozinho se a box cair nos primeiros 10 min. Os dois
  caminhos testados com `sysrq-c`. 40 min de exaustão em 660 sem erro.
- Benchmarks (sbc-bench local, sem upload): em 660 a box ≈ Raspberry Pi 2.

## 14/10, tarde: Wi-Fi e o GPIO que desliga a placa

- Fotos da placa: o Wi-Fi é um módulo **SWB-B42B (BCM4330, do Galaxy S2)** numa plaquinha adaptadora.
  Não responde no Linux.
- Device tree de fábrica extraído de uma ROM Android da mesma placa (V1.2), baixada pelo fio do XDA
  (`fabrica.dts`). Pinos iguais aos do Armbian; ligar a energia do BT (GPIO2_D5) não ajudou.
- **`gpioset gpiochip0 30=1` (GPIO0_D6) cortou a energia da placa.** Power-cycle físico, e o boot seguinte
  entrou em loop de pânico com a DDR em 330: corrupção de memória em transiente. Hipótese em aberto:
  capacitores de desacoplamento sob o SoC não soldados (relato do pocng no fórum LibreELEC).
- Tailscale instalado (`pihole-box`); DNS da tailnet aponta para a box, com Quad9 de reserva. Firewall
  `dnsguard` para a porta 53 não virar resolvedor aberto no IPv6 público da Claro.

## 14/10, noite: rede da casa

- Roteador da Claro sem reserva de IP: IP fixo `192.168.0.4` configurado na própria box (netplan).
- Desde 22:15 o DHCP do roteador entrega `192.168.0.4` + `9.9.9.9`.
- O DNS IPv6 da Claro chega pelo RA e fura o Pi-hole; sem campo para trocar no roteador.
- Rotas lentas: medido que o DNS não é o gargalo (rota da Claro para a Embratel); WARP/ExitLag não ajuda;
  lentidão de dia = bufferbloat (precisaria de SQM num roteador próprio). Nasceu o `netmon`.
- Criada a skill `tvbox-rk3228a` com tudo isto.

## 15/10 a 23/10: ajustes

- 15/10: "The versions file is incomplete" no Pi-hole → cron que repete o `updatechecker` 5 min após o boot.
- 20/10: o `unattended-upgrades` nunca tinha rodado (`APT::Periodic::Enable "0"` do Armbian); corrigido.
  Atualização do Pi-hole passou de semanal para diária. Espelhos lentos do Armbian documentados.
- 21/10: chrony com NTP.br como relógio e servidor de hora da casa (NTP do Pi-hole desligado),
  `fake-hwclock`, e utilitários (vnstat, etckeeper, needrestart, tmux, ncdu, iftop, nload, htop, mtr).
- 22/10: painel da rede da casa na porta 8090 (repositório próprio, `mop4r/painel-rede`) e Uptime Kuma na
  3001 (`ferramentas/instalar-uptime-kuma.sh`).

## 27/10: este repositório

Tudo reunido no GitHub (privado), com as imagens e backups nas Releases.
