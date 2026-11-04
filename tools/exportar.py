"""EXPORTAR CON GODOT SIN QUE SE CAIGA (2026-10-16). La DLL de Windows de TwoVoIP tumba el editor al exportar (signal 8):
se quitan un momento sus lineas `windows` de addons/twovoip/twovoip.gdextension y se devuelven al acabar (pase lo que
pase). Lo usan publicar_apk.py y publicar_parche.py.

  exportar(["--export-release", "Android", "C:/.../Breach v41.apk"])
"""
import os, subprocess

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.join(os.path.expanduser("~"), "Desktop", "GodotEngine", "Godot_v4.7.2-stable_win64_console.exe")
GDEXT = os.path.join(RAIZ, "godot", "addons", "twovoip", "twovoip.gdextension")


def exportar(args, tope=1200):
    original = open(GDEXT, encoding="utf-8").read()
    try:
        # SOLO LA DE DEPURACION (2026-10-20): el editor carga `windows.x86_64` (y eso es lo que lo tumba); la de release
        # (`windows.template_release.x86_64`) el editor no la carga y la exportacion de PC la necesita para llevar la voz
        open(GDEXT, "w", encoding="utf-8").write("\n".join(l for l in original.split("\n") if not l.startswith("windows.x86_64")))
        r = subprocess.run([GODOT, "--headless", "--path", os.path.join(RAIZ, "godot")] + args,
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=tope)
        if "CrashHandler" in r.stdout + r.stderr:
            raise SystemExit("Godot se cayo exportando:\n" + (r.stdout + r.stderr)[-1500:])
        return r
    finally:
        open(GDEXT, "w", encoding="utf-8").write(original)
