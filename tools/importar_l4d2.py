"""Sonidos de Left 4 Dead 2 (github.com/sourcesounds/left4dead2) para las ARMAS y las CRIATURAS del PvE.

AUDIO COMERCIAL CON DERECHOS (Valve), TEMPORAL como el de Battlefield: vale para probar y se quita antes
de publicar borrando godot/sounds/l4d2. Sin esa carpeta el juego vuelve solo a los disparos CC0
(godot/sounds/armas) y a lo de antes.

Salida:
    godot/sounds/l4d2/armas/<arma>/golpe<n>.ogg            el disparo (ya mezclado para juego, con su cola)
    godot/sounds/l4d2/armas/<arma>/recarga_sacar|recarga_meter|recarga_cerrojo<n>.ogg
    godot/sounds/l4d2/armas/<arma>/seco<n>.ogg
    godot/sounds/l4d2/criaturas/<tipo>/<alerta|ataque|dano|muerte|reposo|paso|golpe><n>.ogg

Uso:  python tools/importar_l4d2.py ["C:/Users/usuario 1/Desktop/l4d2-sonidos"]
      (la carpeta `sound` del repositorio: weapons, npc, player)
"""
import glob, os, shutil, sys
import numpy as np
import soundfile as sf

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "Desktop", "l4d2-sonidos")
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "sounds", "l4d2")
TOPE = 10

# arma del juego -> carpeta de weapons/ (la primera manda; las demas dan variantes del disparo)
ARMAS = {
    "carabina_556":    ["rifle"],
    "fusil_762":       ["rifle_ak47"],
    "fusil_bullpup":   ["smg_silenced"],
    "smg_9mm":         ["mp5navy"],
    "smg_compacta":    ["smg"],
    "pdw_57":          ["sg552"],
    "escopeta_bomba":  ["shotgun", "shotgun_chrome"],
    "escopeta_auto":   ["auto_shotgun", "auto_shotgun_spas"],
    "rifle_precision": ["awp", "sniper_military"],
    "pistola_9":       ["pistol"],
    "pistola_45":      ["pistol_silver", "pistol"],
    "revolver_44":     ["magnum"],
    "bot_sks":         ["rifle_desert"],
    "bot_cerrojo":     ["scout", "hunting_rifle"],
    "bot_palanca":     ["hunting_rifle"],
}
# recarga: patrones de nombre dentro de gunother/ (de mejor a peor)
RECARGA = {
    "recarga_sacar":   ["*clip_out*", "*clipout*"],
    "recarga_meter":   ["*clip_in_*", "*clipin.wav", "*clip_in.wav", "*clipin*", "*load_shell*"],
    "recarga_cerrojo": ["*slideforward*", "*slide_forward*", "*boltforward*", "*bolt_forward*",
                        "*boltpullforward*", "*pump*", "*clip_locked*", "*cliplocked*", "*slideback*", "*bolt.wav"],
}

# criatura del PvE -> evento -> patrones (relativos a la carpeta sound/)
I = "npc/infected/"
CRIATURAS = {
    "zombi": {
        "alerta": [I + "alert/becomealert/male/*", I + "alert/becomealert/become_alert*", I + "alert/alert/male/*"],
        "ataque": [I + "action/rageat/male/*", I + "action/rage/male/*"],
        "dano":   [I + "action/been_shot/male/*"],
        "muerte": [I + "action/die/male/*", I + "action/die/death_*"],
        "reposo": [I + "idle/moaning/*", I + "idle/mumbling/*"],
        "paso":   ["player/footsteps/infected/walk/*"],
        "golpe":  [I + "hit/hit_punch_*", "player/pz/hit/claw_hit_flesh_*"],
    },
    "corredor": {
        "alerta": [I + "alert/becomeenraged/female/*", I + "alert/becomealert/female/*", I + "alert/alert/female/*"],
        "ataque": [I + "action/rageat/female/*", I + "action/rage/female/*"],
        "dano":   [I + "action/been_shot/female/*"],
        "muerte": [I + "action/die/female/*"],
        "reposo": [I + "idle/breathing/*"],
        "paso":   ["player/footsteps/infected/run/*"],
        "golpe":  ["player/pz/hit/claw_scrape_*", I + "hit/claw_scrape_*"],
    },
    "saltador": {        # el Hunter
        "alerta": ["player/hunter/voice/alert/*", "player/hunter/voice/warn/*"],
        "ataque": ["player/hunter/voice/attack/hunter_pounce_*", "player/hunter/voice/attack/hunter_attackmix_*", "player/hunter/attack/*"],
        "dano":   ["player/hunter/voice/pain/hunter_painshort_*", "player/hunter/voice/pain/hunter_pain_*"],
        "muerte": ["player/hunter/voice/death/*"],
        "reposo": ["player/hunter/voice/idle/hunter_stalk_*"],
        "paso":   ["player/footsteps/infected/run/*"],
        "golpe":  ["player/hunter/voice/attack/hunter_shred_*"],
    },
    "arrastrado": {      # el Smoker
        "alerta": ["player/smoker/voice/alert/*", "player/smoker/voice/warn/*"],
        "ataque": ["player/smoker/voice/attack/*", "player/smoker/attack/*"],
        "dano":   ["player/smoker/voice/pain/*"],
        "muerte": ["player/smoker/voice/death/*", "player/smoker/death/*"],
        "reposo": ["player/smoker/voice/idle/*"],
        "paso":   ["player/footsteps/infected/walk/*"],
        "golpe":  ["player/smoker/hit/*", "player/pz/hit/claw_hit_flesh_*"],
    },
    "gordo": {           # el Boomer
        "alerta": ["player/boomer/voice/alert/male_*"],
        "ataque": ["player/boomer/voice/vomit/male_boomer_vomit_*", "player/boomer/voice/attack/male_*"],
        "dano":   ["player/boomer/voice/pain/male_boomer_painshort_*", "player/boomer/voice/pain/male_boomer_pain_*"],
        "muerte": ["player/boomer/voice/pain/male_boomer_pain_*"],
        "explota": ["player/boomer/explode/*"],
        "reposo": ["player/boomer/voice/idle/male_boomer_lurk_*"],
        "paso":   ["player/footsteps/boomer/*/*", "player/footsteps/boomer/*"],
        "golpe":  ["player/boomer/hit/*"],
    },
    "escupidor": {       # la Spitter
        "alerta": ["player/spitter/voice/alert/*", "player/spitter/voice/warn/*"],
        "ataque": ["player/spitter/voice/attack/*", "player/spitter/swarm/*"],
        "dano":   ["player/spitter/voice/pain/*"],
        "muerte": ["player/spitter/voice/die/*"],
        "reposo": ["player/spitter/voice/idle/*"],
        "paso":   ["player/footsteps/infected/walk/*"],
        "golpe":  ["player/pz/hit/claw_scrape_*"],
        # el escupitajo: el lanzamiento y el charco de acido burbujeando donde cae
        "escupe": ["player/spitter/spitter_miss_*", "player/boomer/vomit/attack/*"],
        "acido":  ["player/spitter/swarm/spitter_acid_fadeout*"],
    },
    "arana": {           # el Jockey: pequeño, saltarin y con esa risa
        "alerta": ["player/jockey/voice/alert/*", "player/jockey/voice/warn/*", "player/jockey/voice/idle/jockey_spotprey_*"],
        "ataque": ["player/jockey/voice/attack/*"],
        "dano":   ["player/jockey/voice/pain/*"],
        "muerte": ["player/jockey/voice/death/*"],
        "reposo": ["player/jockey/voice/idle/jockey_lurk*", "player/jockey/voice/idle/jockey_recognize*"],
        "paso":   ["player/footsteps/infected/run/*"],
        "golpe":  ["player/pz/hit/claw_hit_flesh_*", "player/pz/hit/zombie_slice_*"],
    },
    "bruto": {           # el Charger
        "alerta": ["player/charger/voice/alert/*", "player/charger/voice/warn/*"],
        "ataque": ["player/charger/voice/attack/*"],
        "dano":   ["player/charger/voice/pain/*"],
        "muerte": ["player/charger/voice/die/*"],
        "reposo": ["player/charger/voice/idle/charger_lurk_*"],
        "paso":   ["player/footsteps/charger/*/*", "player/footsteps/charger/*"],
        "golpe":  ["player/charger/hit/*", "player/charger/loud_chargerimpact_*"],
    },
    "acorazado": {       # el Tank
        "alerta": ["player/tank/voice/yell/*", "player/tank/voice/growl/*"],
        "ataque": ["player/tank/voice/attack/*", "player/tank/attack/*"],
        "dano":   ["player/tank/voice/pain/*"],
        "muerte": ["player/tank/voice/die/*"],
        "reposo": ["player/tank/voice/idle/*", "player/tank/voice/growl/*"],
        "paso":   ["player/footsteps/tank/*/*", "player/footsteps/tank/*"],
        "golpe":  ["player/tank/hit/*", "player/tank/fall/*"],
    },
    "goliat": {          # tambien el Tank (mas grave en el juego: el tono lo baja Audio.voz_criatura)
        "alerta": ["player/tank/voice/yell/*"],
        "ataque": ["player/tank/voice/attack/*", "player/tank/attack/*"],
        "dano":   ["player/tank/voice/pain/*"],
        "muerte": ["player/tank/voice/die/*"],
        "reposo": ["player/tank/voice/growl/*", "player/tank/voice/idle/*"],
        "paso":   ["player/footsteps/tank/*/*", "player/footsteps/tank/*"],
        "golpe":  ["player/tank/hit/*", "player/pz/fall/*"],
    },
    "aullador": {        # la Witch
        "alerta": ["npc/witch/voice/mad/*", "npc/witch/voice/attack/female_shriek_*"],
        "ataque": ["npc/witch/voice/attack/*"],
        "dano":   ["npc/witch/voice/pain/*"],
        "muerte": ["npc/witch/voice/die/*"],
        "reposo": ["npc/witch/voice/idle/*"],
        "paso":   ["player/footsteps/witch/*/*", "player/footsteps/witch/*"],
        "golpe":  ["npc/witch/hit/*"],
    },
}


# LA MUSICA (sound/music): el director de musica de la campaña (campana.gd) elige de aqui
MUSICA = {
    "ambiente":      ["music/contagion/nm_quarantine_*"],         # el fondo de No Mercy, en bucle
    "tension":       ["music/contagion/nm_rabies_*"],             # capas de inquietud que entran de vez en cuando
    "horda_s":       ["music/mob/germs*"],                        # el aviso de que viene la horda, por tamaño
    "horda_m":       ["music/mob/germm*"],
    "horda_l":       ["music/mob/germl*"],
    "horda_x":       ["music/mob/germx*"],
    "combate":       ["music/zombat/horde_*"],                    # mientras dura la horda (bucles de 5,6 s)
    "tank":          ["music/tank/taank.wav", "music/tank/tank.wav"],
    "refugio":       ["music/safe/themonsterswithout_l4d1.wav"],
    "final":         ["music/terror/iamsocold_l4d1.wav"],
    "rescate":       ["music/the_end/skinonourteeth_l4d1.wav"],
    "escapan":       ["music/the_end/finalnail.wav"],
    "muerte":        ["music/undeath/death_l4d1.wav"],
    "todos_muertos": ["music/undeath/leftfordeath_l4d1.wav"],
    "gordo":         ["music/terror/pukricide.wav"],
    "arrastrado":    ["music/terror/tonguetied.wav"],
    "escupidor":     ["music/terror/puddleofyou_l4d1.wav"],
}


def escribir(ruta_wav, destino):
    x, sr = sf.read(ruta_wav, always_2d=True)
    x = x.astype(np.float32)
    # POR TROZOS: libsndfile revienta (sin mensaje, codigo 127) escribiendo en OGG una pista larga de golpe
    with sf.SoundFile(destino, "w", sr, x.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])


def copiar(archivos, carpeta, nombre):
    archivos = [f for f in dict.fromkeys(archivos) if f.lower().endswith(".wav") and os.path.isfile(f)]
    for n, f in enumerate(archivos[:TOPE], 1):
        escribir(f, os.path.join(carpeta, "%s%d.ogg" % (nombre, n)))
    return min(len(archivos), TOPE)


def main():
    dst = os.path.abspath(DST)
    os.makedirs(dst, exist_ok=True)
    for sub in glob.glob(os.path.join(dst, "*")):
        shutil.rmtree(sub, ignore_errors=True) if os.path.isdir(sub) else os.remove(sub)
    w = os.path.join(SRC, "weapons")
    for arma, carpetas in ARMAS.items():
        car = os.path.join(dst, "armas", arma)
        os.makedirs(car, exist_ok=True)
        fuego = []
        for c in carpetas:
            fuego += [f for f in sorted(glob.glob(os.path.join(w, c, "gunfire", "*.wav"))) if "incendiary" not in f]
        info = ["golpe %d" % copiar(fuego, car, "golpe")]
        otros = os.path.join(w, carpetas[0], "gunother")
        for paso, pats in RECARGA.items():
            fs = []
            for p in pats:
                fs = sorted(glob.glob(os.path.join(otros, p)))
                if fs:
                    break
            info.append("%s %d" % (paso, copiar(fs, car, paso)))
        seco = os.path.join(w, "clipempty_pistol.wav" if "pistol" in arma or "revolver" in arma else "clipempty_rifle.wav")
        info.append("seco %d" % copiar([seco], car, "seco"))
        print("%-16s %s" % (arma, " · ".join(info)))
    for tipo, eventos in CRIATURAS.items():
        car = os.path.join(dst, "criaturas", tipo)
        os.makedirs(car, exist_ok=True)
        info = []
        for ev, pats in eventos.items():
            fs = []
            for p in pats:
                fs += sorted(glob.glob(os.path.join(SRC, p)))
            info.append("%s %d" % (ev, copiar(fs, car, ev)))
        print("%-16s %s" % (tipo, " · ".join(info)))
    car = os.path.join(dst, "musica")
    os.makedirs(car, exist_ok=True)
    info = []
    for clave, pats in MUSICA.items():
        fs = []
        for p in pats:
            fs += sorted(glob.glob(os.path.join(SRC, p)))
        info.append("%s %d" % (clave, copiar(fs, car, clave)))
    print("musica           " + " · ".join(info))
    mb = sum(os.path.getsize(f) for f in glob.glob(os.path.join(dst, "**", "*.ogg"), recursive=True)) / 1048576
    print("total %.1f MB en %s" % (mb, dst))


if __name__ == "__main__":
    main()
