"""PUBLICAR LA APK EN EL SERVIDOR DEL PC (2026-10-16, pedido: "me canse de pasar APK por APK").

Copia la APK a servidor/apk/Breach.apk y escribe servidor/apk/version.json con su version (la de
godot/export_presets.cfg, la que pone tools/subir_version.py). Desde ese momento, al abrir el juego, los que tengan una
version anterior ven el aviso ACTUALIZAR, que baja la APK de este servidor (/apk/Breach.apk); Android pide "Instalar".
No hace falta reiniciar el servidor.

  python tools/publicar_apk.py                     (la "Breach vN.apk" mas nueva del escritorio)
  python tools/publicar_apk.py "ruta/a/la.apk"
  python tools/publicar_apk.py --url=https://www.mediafire.com/...   (ACTUALIZAR lleva a ese link)
"""
import glob, json, os, re, shutil, sys, time

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DEST = os.path.join(RAIZ, "servidor", "apk")


def version():
    s = open(os.path.join(RAIZ, "godot", "export_presets.cfg"), encoding="utf-8").read()
    code = int(re.search(r'^version/code=(\d+)', s, re.M).group(1))
    nombre = re.search(r'^version/name="([^"]*)"', s, re.M).group(1)
    return code, nombre


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        apk = args[0]
    else:
        escritorio = os.path.join(os.path.expanduser("~"), "Desktop")
        apks = glob.glob(os.path.join(escritorio, "Breach v*.apk"))
        if not apks:
            sys.exit("no hay ninguna 'Breach vN.apk' en el escritorio")
        apk = max(apks, key=os.path.getmtime)
    code, nombre = version()
    os.makedirs(DEST, exist_ok=True)
    tmp = os.path.join(DEST, "Breach.apk.subiendo")
    shutil.copyfile(apk, tmp)
    os.replace(tmp, os.path.join(DEST, "Breach.apk"))     # de golpe: nadie baja una a medias
    mb = round(os.path.getsize(os.path.join(DEST, "Breach.apk")) / 1048576)
    info = {"code": code, "nombre": nombre, "mb": mb, "fecha": time.strftime("%Y-%m-%d %H:%M")}
    # --url=<link>: el boton ACTUALIZAR lleva ahi (p.ej. MediaFire) en vez de bajarla de este servidor (index.js redirige)
    for a in sys.argv[1:]:
        if a.startswith("--url="):
            info["url"] = a[6:]
    json.dump(info, open(os.path.join(DEST, "version.json"), "w", encoding="utf-8"))
    print("publicada %s como version %s (code %d, %d MB)" % (os.path.basename(apk), nombre, code, mb))
    # LA BASE DE LOS PARCHES (tools/publicar_parche.py): el .pck de esta misma version, y las huellas de lo que un parche
    # no puede cambiar. Los parches de la APK anterior ya no valen: fuera.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from exportar import exportar
    from publicar_parche import huellas
    for f in os.listdir(DEST):
        if (f.startswith("parche") and not f.startswith("parche_pc")) or (f.startswith("base_") and not f.startswith("base_pc_")
                and not f.startswith("base_%d." % code)):   # lo del PC va aparte (tools/exportar_pc.py)
            os.remove(os.path.join(DEST, f))
    base = os.path.join(DEST, "base_%d.pck" % code)
    print("exportando la base de los parches...")
    exportar(["--export-pack", "Android", base])
    json.dump(huellas(), open(os.path.join(DEST, "base_%d.json" % code), "w", encoding="utf-8"))
    print("base de los parches lista: %s (%d MB)" % (os.path.basename(base), os.path.getsize(base) // 1048576))


if __name__ == "__main__":
    main()
