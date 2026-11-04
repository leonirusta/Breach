"""SUBE LA VERSION DEL JUEGO ANTES DE EXPORTAR UN APK NUEVO PARA LA TIENDA  (2026-10-01)

    python tools/subir_version.py [--nombre=1.0.3] [--ver]

El aviso de version nueva (godot/scripts/aviso_version.gd) compara el numero de ESTE juego (Settings.VERSION_APP) con el
que marque el panel (pestana VERSION). Ese numero tiene que ser el mismo que el "version code" del APK
(godot/export_presets.cfg, version/code), que ademas la Play Store exige que suba en cada subida. Esto sube los dos a la
vez (+1); --nombre= cambia tambien el nombre que ve la gente (version/name). --ver solo dice cual hay.
Luego: exportar el APK, subirlo, y en el panel poner esa version como la ULTIMA (y obligatoria si hace falta).
"""
import io
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRESETS = os.path.join(RAIZ, "godot", "export_presets.cfg")
SETTINGS = os.path.join(RAIZ, "godot", "scripts", "settings.gd")


def leer(p):
    with io.open(p, encoding="utf-8") as f:
        return f.read()


def escribir(p, s):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def main():
    pre = leer(PRESETS)
    st = leer(SETTINGS)
    codigos = re.findall(r"^version/code=(\d+)$", pre, re.M)
    nombres = re.findall(r'^version/name="([^"]*)"$', pre, re.M)
    m = re.search(r"^const VERSION_APP := (\d+)$", st, re.M)
    if not codigos or not m:
        raise SystemExit("no encuentro version/code en export_presets.cfg o VERSION_APP en settings.gd")
    apk, juego = int(codigos[0]), int(m.group(1))
    print("ahora: APK version/code %d (\"%s\") · juego VERSION_APP %d" % (apk, nombres[0] if nombres else "?", juego))
    if "--ver" in sys.argv:
        return
    nueva = max(apk, juego) + 1
    pre = re.sub(r"^version/code=\d+$", "version/code=%d" % nueva, pre, flags=re.M)
    for a in sys.argv[1:]:
        if a.startswith("--nombre="):
            pre = re.sub(r'^version/name="[^"]*"$', 'version/name="%s"' % a[9:], pre, flags=re.M)
    st = re.sub(r"^const VERSION_APP := \d+$", "const VERSION_APP := %d" % nueva, st, count=1, flags=re.M)
    escribir(PRESETS, pre)
    escribir(SETTINGS, st)
    # y la del cargador de parches (godot/scripts/parche.gd): un parche solo vale para su APK
    pa = os.path.join(RAIZ, "godot", "scripts", "parche.gd")
    if os.path.exists(pa):
        escribir(pa, re.sub(r"^const APK_CODE := \d+", "const APK_CODE := %d" % nueva, leer(pa), count=1, flags=re.M))
    print("nueva: %d (APK y juego). Exporta el APK, subelo y marca %d en el panel (VERSION)." % (nueva, nueva))


if __name__ == "__main__":
    main()
