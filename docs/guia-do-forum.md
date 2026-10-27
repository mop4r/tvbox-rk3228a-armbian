# Instalar Armbian no box RK3228A — guia (14/10/2026)

Juntando: análise do multitool (`analise/multitool/README.md`), o tópico do fórum Armbian
(105 páginas, resumido), e o vídeo "Instalando Linux em TV Box com RK322X!" (título confirmado;
legendas bloqueadas pelo YouTube). Placa alvo: **RK3228A, eMMC Samsung ~7,3 GB** (detectado nos
logs do RKDevTool).

Imagem já baixada: `imagens/Armbian_community_26.11.0-trunk.83_Rk322x-box_trixie_current_6.18.55_minimal.img.xz`.
Loader já aqui: `original/soltos/loaders/rk322x_loader_v1.10.256.bin`.

## Caminho A — Multitool pelo cartão SD (recomendado pelo fórum)

Precisa de um cartão microSD e um leitor. É o jeito mais seguro.

1. **Gravar o multitool no SD.** Descompacte `original/soltos/multitool-rk322x.xz` para um `.img` e
   grave no SD com o **Rufus** (já está em `original/soltos/rufus-4.14.exe`), balenaEtcher ou `dd`.
2. **Copiar a imagem do Armbian** para a partição `MULTITOOL` (NTFS) do SD, na pasta `images/`.
   Pode deixar compactada (`.img.xz` serve — o multitool descompacta na hora).
3. **Dar boot pelo SD.** Com o box desligado, insira o SD e ligue. Se o box tiver Android de
   fábrica e ignorar o SD, use um destes para forçar:
   - Segurar o microbotão de reset (furo atrás, às vezes atrás da saída AV) ao ligar; ou
   - Apagar os primeiros 8 MB do eMMC antes (o SoC então cai no SD) — dá para fazer pelo próprio
     multitool ("Erase flash") se conseguir entrar nele uma vez.
4. **No menu do multitool:**
   - (opcional, recomendado) **"Backup flash"** — salva o firmware de fábrica.
   - **"Burn image to flash"** → destino **`mmcblk2`** (o eMMC) → escolher a imagem do Armbian.
   - O multitool grava a imagem crua no eMMC e, no rk322x, ajusta o Command Rate do DDR sozinho.
5. **Finalizar:** "Shutdown", tirar o SD, religar. O **primeiro boot leva alguns minutos**
   (redimensiona o filesystem). Depois: senha de root + usuário, e `sudo rk322x-config` (LEDs,
   Wi-Fi, eMMC em alta velocidade) e `sudo armbian-config`.

## Caminho B — PC por USB (maskrom), sem cartão SD

Usa o modo maskrom (o mesmo que o MiFlash/RKDevTool usa). A placa é detectada como VID `2207` PID `320b`.

1. **Entrar em maskrom:** box desligado, cabo USB (OTG) no PC, segurar o reset ou curto no pino de
   clock do eMMC ao ligar. Conferir no Gerenciador de Dispositivos / `lsusb` o ID `2207:320b`.
2. **Trocar o driver** no Windows para WinUSB (com o Zadig) se o `rkdeveloptool` não enxergar — o
   `rockusb.sys` da Rockchip não serve para o rkdeveloptool.
3. **Gravar** (descompacte o `.img.xz` antes):
   ```
   rkdeveloptool db rk322x_loader_v1.10.256.bin     # sobe o loader
   rkdeveloptool wl 0x0 Armbian_...6.18.55_minimal.img   # grava a imagem crua no setor 0
   rkdeveloptool rd                                  # reinicia
   ```
   (O fonte do rkdeveloptool está em `original/rkdeveloptool-master`; no Windows precisa de build
   com libusb, ou usar o RKDevTool GUI — **2.86**, não a 2.96, que falha a troca de mídia no rk322x.)

## Armadilhas que valem para o RK3228A (do fórum)

- **Trust OS trava o boot** em alguns RK3228A (2026): a imagem pisca e apaga, LED vermelho fixo.
  Se acontecer: tentar uma imagem com Trust OS alternativo, ou os offsets corrigidos (TrustOS 0x2000,
  u-boot 0x4000) + `rk322x_tee.bin` antigo. Dar `apt-mark hold` no u-boot depois de instalar.
- **DDR Command Rate errado** = instável / não boota. O multitool acerta isso sozinho; a ferramenta
  do PC precisa reproduzir (byte 16 posições antes da assinatura `a7866565`, 0x00=1T/0x01=2T).
- **Não confundir RK3228 (DDR2) com RK3229**, nem usar o loader `RK32xxLoader V2.15` (é de outro chip).
  Usar **`rk322x_loader_v1.10.256.bin`**.
- **Fabricante errado** no rkdeveloptool (mostra Samsung sendo Kingston/Hynix) é esperado, ignore.
- **Testar sempre pelo SD antes de gravar no eMMC** — grava ruim = soft-brick.
- **Sem vídeo/HDMI**: sem correção universal; pistas são overlay `led-conf`, Trust OS alternativo,
  testar pelo SD. UART serial a 115200 bps (4º pino à direita do slot SD) ajuda no diagnóstico.
- **Imagem**: usar a mainline "current" (a que baixamos, kernel 6.18). Legacy 4.4 está descontinuado.
  Para mídia com decodificação por hardware, o jock sugere Bookworm 6.18 (o mpv do Trixie ainda falha).

## O que eu posso fazer no PC vs o que é físico (seu)

Eu preparo tudo (imagem baixada e conferida, loader, scripts, este guia). **Os passos físicos são
seus**: gravar o SD, pôr o box em boot/maskrom (reset/curto), e escolher no menu. Não consigo
operar o aparelho daqui. Se quiser o Caminho B, posso tentar montar o `rkdeveloptool` para Windows
ou te guiar pelo RKDevTool 2.86.
