"""LA VERSION DE PC (2026-10-20, pedido: "compilame la version para PC; tambien se actualizara con los mismos parches").

Exporta el preset "Windows" a Escritorio/Breach PC (Breach.exe + Breach.pck) y guarda su .pck como base de los parches del
PC (servidor/apk/base_pc_<code>.pck): desde ahi, tools/publicar_parche.py saca tambien parche_pc.pck y el juego del PC lo
baja solo (godot/scripts/parche.gd, /parche/info?plat=pc).

  python tools/exportar_pc.py
"""
import os, re, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exportar import exportar, RAIZ

DESTINO = os.path.join(os.path.expanduser("~"), "Desktop", "Breach PC")


def main():
    pres = open(os.path.join(RAIZ, "godot", "export_presets.cfg"), encoding="utf-8").read()
    code = int(re.search(r"version/code=(\d+)", pres).group(1))
    os.makedirs(DESTINO, exist_ok=True)
    exe = os.path.join(DESTINO, "Breach.exe").replace("\\", "/")
    print("exportando la version de PC (%s)..." % exe)
    r = exportar(["--export-release", "Windows", exe])
    pck = os.path.join(DESTINO, "Breach.pck")
    if not os.path.exists(pck):
        sys.exit("Godot no genero el .pck:\n" + (r.stdout + r.stderr)[-1500:])
    base = os.path.join(RAIZ, "servidor", "apk", "base_pc_%d.pck" % code)
    # UN ENLACE, NO UNA COPIA (el disco de este PC va justo): la base es el mismo archivo que el .pck del PC exportado.
    # OJO: si se vuelve a exportar, la base cambia con el (y los parches del PC empiezan de cero, ver abajo)
    if os.path.exists(base):
        os.remove(base)
    try:
        os.link(pck, base)
    except OSError:
        shutil.copyfile(pck, base)
    for f in ("parche_pc.json", "parche_pc.pck"):
        p = os.path.join(RAIZ, "servidor", "apk", f)
        if os.path.exists(p):
            os.remove(p)                     # una base nueva: los parches del PC empiezan de cero
    mb = sum(os.path.getsize(os.path.join(DESTINO, f)) for f in os.listdir(DESTINO)) / 1048576.0
    print("== version de PC en %s (%.0f MB), base de parches %s" % (DESTINO, mb, os.path.basename(base)))


if __name__ == "__main__":
    main()
