"""PUBLICAR UN PARCHE EN EL SERVIDOR DEL PC (2026-10-16, pedido: "que no descargue el juego entero, solo los archivos
que cambiaron").

Exporta con Godot SOLO lo que cambio respecto a la base de la APK publicada (--export-patch con la base que guardo
tools/publicar_apk.py) y lo deja en servidor/apk/parche.pck + parche.json ({apk, n, mb, sha256, fecha}). Los jugadores
con esa APK lo bajan al abrir el juego (godot/scripts/parche.gd) y se aplica al reiniciar. Cada parche lleva TODO lo
cambiado desde la APK (no se encadenan): el que se salto uno baja solo el ultimo.

Desde la APK 43 el MOTOR C++ tambien va en el parche (motor_android / motor_windows, ver register_types.cpp).
NO SIRVE (y lo dice) si cambio la libreria de la voz (addons/twovoip/libs) o project.godot (autoloads, ajustes). Para eso: subir_version + exportar la APK +
publicar_apk.py.

  python tools/publicar_parche.py
"""
import hashlib, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exportar import exportar, RAIZ

APK = os.path.join(RAIZ, "servidor", "apk")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def huellas():
    """Lo que un parche no puede cambiar: si alguna de estas cambio desde la base, hace falta la APK entera"""
    out = {}
    for rel in ["godot/bin/libbreach_voxel.android.template_release.arm64.so",
                "godot/addons/twovoip/libs/libtwovoip.android.template_release.arm64.so", "godot/project.godot"]:
        p = os.path.join(RAIZ, rel)
        if os.path.exists(p):
            out[rel] = sha(p)
    return out


def main():
    info_apk = json.load(open(os.path.join(APK, "version.json"), encoding="utf-8"))
    code = int(info_apk["code"])
    base = os.path.join(APK, "base_%d.pck" % code)
    base_json = os.path.join(APK, "base_%d.json" % code)
    if not os.path.exists(base):
        sys.exit("no hay base de la APK %d (servidor/apk/base_%d.pck): publica la APK con tools/publicar_apk.py" % (code, code))
    antes = json.load(open(base_json, encoding="utf-8")) if os.path.exists(base_json) else {}
    ahora = huellas()
    # EL MOTOR (C++) YA VA EN EL PARCHE (2026-10-16): lo baja parche.gd y lo carga el portero de la libreria de la APK
    # (godot/extension/src/register_types.cpp). Solo desde la APK 43, la primera con portero.
    MOTOR_ANDROID = "godot/bin/libbreach_voxel.android.template_release.arm64.so"
    MOTOR_WINDOWS = "godot/bin/libbreach_voxel.windows.template_release.x86_64.dll"
    motor_cambio = bool(antes.get(MOTOR_ANDROID)) and antes.get(MOTOR_ANDROID) != ahora.get(MOTOR_ANDROID)
    if motor_cambio and code < 43:
        sys.exit("ESTO NO VA EN UN PARCHE: cambio el motor y la APK %d no tiene portero (hace falta la 43 o mas)." % code)
    cambiado = [k for k in ahora if k != MOTOR_ANDROID and antes.get(k) and antes[k] != ahora[k]]
    if cambiado and "--forzar" not in sys.argv:
        sys.exit("ESTO NO VA EN UN PARCHE: cambio %s.\nHace falta la APK entera: python tools/subir_version.py, exportar, "
                 "python tools/publicar_apk.py (o --forzar si sabes lo que haces)." % ", ".join(cambiado))
    out = os.path.join(APK, "parche_nuevo.pck")
    print("exportando el parche (solo lo cambiado desde la APK %d)..." % code)
    exportar(["--export-patch", "Android", out, "--patches", base])
    if not os.path.exists(out):
        sys.exit("Godot no genero el parche")
    # SIN NADA QUE PARCHEAR, NO SE PUBLICA (2026-10-20): un .pck vacio colgaba el arranque del juego
    if os.path.getsize(out) < 4096:
        os.remove(out)
        print("nada cambiado para Android desde la APK %d: no se publica parche" % code)
        parche_pc(code, None)
        return
    viejo = os.path.join(APK, "parche.json")
    n = 1
    if os.path.exists(viejo):
        v = json.load(open(viejo, encoding="utf-8"))
        if int(v.get("apk", -1)) == code:
            n = int(v.get("n", 0)) + 1
    os.replace(out, os.path.join(APK, "parche.pck"))
    p = os.path.join(APK, "parche.pck")
    kb = os.path.getsize(p) / 1024.0
    info = {"apk": code, "n": n, "mb": round(kb / 1024.0, 2), "sha256": sha(p), "fecha": time.strftime("%Y-%m-%d %H:%M")}
    if motor_cambio:
        import shutil
        info["motor"] = {}
        for plat, rel in [("android", MOTOR_ANDROID), ("windows", MOTOR_WINDOWS)]:
            src = os.path.join(RAIZ, rel)
            if os.path.exists(src):
                dst = os.path.join(APK, "motor_" + plat)
                shutil.copyfile(src, dst + ".subiendo")
                os.replace(dst + ".subiendo", dst)
                info["motor"][plat] = {"sha256": sha(dst), "mb": round(os.path.getsize(dst) / 1048576.0, 2)}
        info["mb"] = round(info["mb"] + info["motor"].get("android", {}).get("mb", 0.0), 2)
        print("el parche lleva el MOTOR (C++): %s" % ", ".join(info["motor"].keys()))
    else:
        for plat in ["android", "windows"]:
            if os.path.exists(os.path.join(APK, "motor_" + plat)):
                os.remove(os.path.join(APK, "motor_" + plat))
    json.dump(info, open(viejo, "w", encoding="utf-8"))
    print("parche %d publicado para la APK %d: %.0f KB" % (n, code, kb))
    parche_pc(code, info.get("motor"))


def parche_pc(code, motor):
    """EL PARCHE DEL PC (2026-10-20): lo mismo contra la base del PC (servidor/apk/base_pc_<code>.pck, la deja
    tools/exportar_pc.py), en parche_pc.pck / parche_pc.json. Sin base del PC, nada."""
    base = os.path.join(APK, "base_pc_%d.pck" % code)
    if not os.path.exists(base):
        print("(sin base del PC: no hay parche para el PC; se hace con python tools/exportar_pc.py)")
        return
    out = os.path.join(APK, "parche_pc_nuevo.pck")
    exportar(["--export-patch", "Windows", out, "--patches", base])
    if not os.path.exists(out):
        print("Godot no genero el parche del PC")
        return
    if os.path.getsize(out) < 4096:
        os.remove(out)
        print("nada cambiado para el PC desde su version: no se publica parche del PC")
        return
    viejo = os.path.join(APK, "parche_pc.json")
    n = 1
    if os.path.exists(viejo):
        v = json.load(open(viejo, encoding="utf-8"))
        if int(v.get("apk", -1)) == code:
            n = int(v.get("n", 0)) + 1
    p = os.path.join(APK, "parche_pc.pck")
    os.replace(out, p)
    kb = os.path.getsize(p) / 1024.0
    info = {"apk": code, "n": n, "mb": round(kb / 1024.0, 2), "sha256": sha(p), "fecha": time.strftime("%Y-%m-%d %H:%M")}
    if motor and motor.get("windows"):
        info["motor"] = {"windows": motor["windows"]}
    json.dump(info, open(viejo, "w", encoding="utf-8"))
    print("parche del PC %d publicado: %.0f KB" % (n, kb))


if __name__ == "__main__":
    main()
