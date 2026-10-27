"""Publica a versão pública deste projeto no GitHub.

A pasta local (e a skill tvbox-rk3228a) guardam a versão COMPLETA, com IPs, nomes e endereços da casa.
O GitHub recebe uma cópia limpa: este script copia os arquivos versionáveis para `publico/` (clone do
GitHub), troca os dados particulares por exemplos segundo um mapa que fica FORA do repositório, confere
que nada particular sobrou e só então faz commit e push.

Nunca copiar do GitHub (ou de `publico/`) de volta para a pasta local: a versão de lá é a limpa.

Uso:  python -I ferramentas/publicar.py "mensagem do commit"
      python -I ferramentas/publicar.py --conferir      (só gera e confere, sem commit)
Mapa: $PUBLICO_MAPA ou ~/workspace/scripts/multiclaude-queue/credenciais/rk322x-flash/publico.json
"""
import json
import os
import shutil
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUB = os.path.join(RAIZ, "publico")
CRED = os.path.join(os.path.expanduser("~"), "workspace", "scripts", "multiclaude-queue", "credenciais")
MAPA = os.environ.get("PUBLICO_MAPA", os.path.join(CRED, "rk322x-flash", "publico.json"))

INCLUIR = [
    "README.md", "LICENSE", ".gitignore", ".gitattributes",
    "docs", "arquivos-da-box", "ferramentas", "scripts",
    "analise/android-dtb", "analise/ghidra_scripts", "analise/scripts", "analise/snapshots",
    "analise/multitool/README.md", "analise/multitool/autoflash.sh", "analise/multitool/multitool.sh",
]
BINARIOS = (".dtb", ".bin", ".img", ".xz")


def git(*args, check=True):
    return subprocess.run(["git", "-C", PUB, *args], check=check, capture_output=True, text=True, encoding="utf-8")


def segredos(mapa):
    """Valores dos .env listados no mapa (pastas de credenciais/), que nunca podem ir a público."""
    vals = []
    for f in [os.path.join(CRED, n, ".env") for n in mapa.get("envs", [])]:
        if not os.path.exists(f):
            continue
        for linha in open(f, encoding="utf-8", errors="replace"):
            if "=" in linha and not linha.lstrip().startswith("#"):
                k, v = linha.strip().split("=", 1)
                v = v.strip().strip("\"'")
                # senhas, chaves e segredos; IP, usuário e URL não são segredo (os IPs particulares estão nos proibidos)
                if len(v) >= 6 and not any(x in k.upper() for x in ("IP", "USER", "URL")):
                    vals.append(v)
    return vals


def copiar():
    for nome in os.listdir(PUB):
        if nome == ".git":
            continue
        p = os.path.join(PUB, nome)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    for rel in INCLUIR:
        orig, dest = os.path.join(RAIZ, rel), os.path.join(PUB, rel)
        if not os.path.exists(orig):
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.isdir(orig):
            shutil.copytree(orig, dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".env"))
        else:
            shutil.copy2(orig, dest)


def arquivos_texto():
    for dp, dn, fn in os.walk(PUB):
        dn[:] = [d for d in dn if d != ".git"]
        for f in fn:
            if not f.endswith(BINARIOS):
                yield os.path.join(dp, f)


def limpar(mapa):
    for p in arquivos_texto():
        try:
            s = open(p, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        novo = s
        for velho, troca in mapa["trocas"]:
            novo = novo.replace(velho, troca)
        if novo != s:
            open(p, "w", encoding="utf-8", newline="").write(novo)


def conferir(mapa):
    proibidos = [x.lower() for x in mapa["proibidos"]] + [v.lower() for v in segredos(mapa)]
    achados = []
    for dp, dn, fn in os.walk(PUB):
        dn[:] = [d for d in dn if d != ".git"]
        for f in fn:
            p = os.path.join(dp, f)
            conteudo = open(p, "rb").read().decode("utf-8", "replace").lower()
            for i, x in enumerate(proibidos):
                if x in conteudo:
                    rotulo = mapa["proibidos"][i] if i < len(mapa["proibidos"]) else "<valor de .env>"
                    achados.append(f"{os.path.relpath(p, PUB)}: {rotulo}")
    return achados


def main():
    if not os.path.isdir(os.path.join(PUB, ".git")):
        sys.exit(f"falta o clone público em {PUB} (gh repo clone mop4r/tvbox-rk3228a-armbian publico)")
    mapa = json.load(open(MAPA, encoding="utf-8"))
    git("pull", "--ff-only", "-q")
    copiar()
    limpar(mapa)
    achados = conferir(mapa)
    if achados:
        print("PARTICULAR AINDA PRESENTE, nada foi publicado:")
        print("\n".join(achados))
        sys.exit(1)
    git("add", "-A")
    mudou = git("status", "--porcelain").stdout.strip()
    print(mudou or "nada mudou")
    if not mudou or (len(sys.argv) > 1 and sys.argv[1] == "--conferir"):
        return
    msg = sys.argv[1] if len(sys.argv) > 1 else "Atualiza a partir da versão local"
    git("-c", "user.name=mop4r", "-c", f"user.email={mapa['email_commit']}", "commit", "-q", "-m",
        msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")
    git("push", "-q")
    print("publicado:", git("log", "--oneline", "-1").stdout.strip())


if __name__ == "__main__":
    main()
