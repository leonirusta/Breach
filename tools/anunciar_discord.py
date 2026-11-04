"""ANUNCIAR UNA ACTUALIZACION EN DISCORD (2026-10-16, pedido: "vas a notificar a la gente en el canal de actualizaciones").

Publica en #actualizaciones-breach del servidor "Breach Teardown" por su webhook. La URL vive en
servidor/discord_webhook.txt (fuera de git: quien la tenga puede escribir en el canal).

  python tools/anunciar_discord.py "Titulo" "linea 1" "linea 2" ...
  python tools/anunciar_discord.py --archivo=notas.txt "Titulo"     (una novedad por linea)
"""
import json, os, sys, urllib.request

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WEBHOOK = os.path.join(RAIZ, "servidor", "discord_webhook.txt")


def anunciar(titulo, lineas, version=None):
    url = open(WEBHOOK, encoding="utf-8").read().strip()
    desc = "\n".join("• " + l for l in lineas if l.strip())
    embed = {"title": titulo, "description": desc[:4000], "color": 0xE8541C}
    if version:
        embed["footer"] = {"text": "Versión %s" % version}
    cuerpo = json.dumps({"username": "Breach", "embeds": [embed]}).encode("utf-8")
    req = urllib.request.Request(url, data=cuerpo, method="POST",
        headers={"Content-Type": "application/json", "User-Agent": "Breach/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.status


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    arch = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--archivo=")), None)
    ver = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--version=")), None)
    if not args:
        sys.exit(__doc__)
    lineas = open(arch, encoding="utf-8").read().splitlines() if arch else args[1:]
    print("publicado:", anunciar(args[0], lineas, ver))
