"""LOS PARCHES DEL PANEL (Breach Admin, 2026-10-28). Como publicar_parche.py, para admin/:

  python tools/publicar_parche_admin.py --apk     exporta la APK del panel (al escritorio) y guarda su base
  python tools/publicar_parche_admin.py           publica un parche con lo cambiado desde esa APK

La base va a servidor/apk/admin_base_<code>.pck; el parche a admin_parche.pck + admin_parche.json ({apk, n, sha256}),
que sirve el servidor en /parche/admin/info y /parche/admin/Admin.pck. Lo baja admin/scripts/parche_admin.gd.
Si cambia admin/project.godot o parche_admin.gd hace falta APK entera (subir version/code y APK_CODE a la vez).
"""
import hashlib, json, os, re, shutil, subprocess, sys, time
RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.join(os.path.expanduser("~"), "Desktop", "GodotEngine", "Godot_v4.7.2-stable_win64_console.exe")
ADMIN = os.path.join(RAIZ, "admin")
APK = os.path.join(RAIZ, "servidor", "apk")
ESCRITORIO = os.path.join(os.path.expanduser("~"), "Desktop")


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def godot(args):
    r = subprocess.run([GODOT, "--headless", "--path", ADMIN] + args, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=1200)
    if "CrashHandler" in r.stdout + r.stderr:
        sys.exit("Godot se cayo:\n" + (r.stdout + r.stderr)[-1500:])
    return r


def code():
    return int(re.search(r"version/code=(\d+)", open(os.path.join(ADMIN, "export_presets.cfg"), encoding="utf-8").read()).group(1))


def huella():
    return sha(os.path.join(ADMIN, "project.godot")) + sha(os.path.join(ADMIN, "scripts", "parche_admin.gd"))


def main():
    c = code()
    base = os.path.join(APK, "admin_base_%d.pck" % c)
    if "--apk" in sys.argv:
        apk = os.path.join(ADMIN, "..", "BreachAdmin.apk")
        godot(["--export-release", "Android", os.path.abspath(apk)])
        if not os.path.exists(apk):
            sys.exit("no se genero la APK")
        godot(["--export-pack", "Android", base])
        json.dump({"code": c, "huella": huella()}, open(base + ".json", "w"))
        dst = os.path.join(ESCRITORIO, "BreachAdmin.apk")
        shutil.copyfile(apk, dst)
        print("APK del panel %d en %s (%.1f MB), base guardada" % (c, dst, os.path.getsize(dst) / 1048576))
        return
    if not os.path.exists(base):
        sys.exit("no hay base de la APK del panel %d: python tools/publicar_parche_admin.py --apk" % c)
    if json.load(open(base + ".json")).get("huella") != huella():
        sys.exit("cambio admin/project.godot o parche_admin.gd: hace falta APK entera (--apk, subiendo version/code y APK_CODE)")
    out = os.path.join(APK, "admin_parche_nuevo.pck")
    godot(["--export-patch", "Android", out, "--patches", base])
    if not os.path.exists(out) or os.path.getsize(out) < 4096:
        if os.path.exists(out):
            os.remove(out)
        print("nada cambiado en el panel: no se publica")
        return
    j = os.path.join(APK, "admin_parche.json")
    n = 1
    if os.path.exists(j):
        v = json.load(open(j))
        if int(v.get("apk", -1)) == c:
            n = int(v.get("n", 0)) + 1
    p = os.path.join(APK, "admin_parche.pck")
    os.replace(out, p)
    json.dump({"apk": c, "n": n, "sha256": sha(p), "fecha": time.strftime("%Y-%m-%d %H:%M")}, open(j, "w"))
    print("parche del panel %d publicado (APK %d): %.0f KB" % (n, c, os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
