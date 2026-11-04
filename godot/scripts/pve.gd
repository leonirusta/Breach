extends Node
const Estadisticas := preload("res://scripts/estadisticas.gd")
## MODO PvE: oleadas de criaturas contra el jugador (lobby: columna izquierda). Diez oleadas que van
## metiendo mas bichos y mas duros; en la decima sale el GOLIAT, el jefe final. Entre oleada y oleada
## hay un respiro para recargar y recolocarse.
##
## Los tipos y su dureza viven en TIPOS; lo que sale en cada oleada, en OLEADAS. Los modelos se hacen en
## Blender (tools/blender/criaturas) y se cargan de res://criaturas/<tipo>.glb si existen.

const CriaturaScript := preload("res://scripts/criatura.gd")
const Minimapa := preload("res://scripts/minimap.gd")
const DESCANSO := 8.0              ## s entre oleadas
const MAX_VIVOS := 14              ## criaturas a la vez como mucho: el resto espera su turno
const SALIDA_CADA := 0.7           ## s entre una salida y la siguiente
const RADIO_SALIDA := Vector2(18.0, 34.0)   ## a cuanto del jugador aparecen

const TIPOS := {
	"zombi": {"nombre": "Zombi", "vida": 90.0, "velocidad": 1.9, "dano": 12.0, "alcance": 1.5, "cadencia": 1.3,
		"amago": 0.45, "alto": 1.8, "radio": 0.35, "color": Color(0.35, 0.45, 0.30), "puntos": 100,
		"modelo": "res://criaturas/zombi.glb"},
	"corredor": {"nombre": "Corredor", "vida": 55.0, "velocidad": 4.6, "vel_correr": 3.0, "dano": 9.0, "alcance": 1.4,
		"cadencia": 0.8, "amago": 0.25, "alto": 1.75, "radio": 0.32, "color": Color(0.55, 0.33, 0.28), "puntos": 120,
		"modelo": "res://criaturas/corredor.glb"},
	"bruto": {"nombre": "Bruto", "vida": 420.0, "velocidad": 1.6, "dano": 35.0, "alcance": 2.2, "cadencia": 2.0,
		"amago": 0.7, "alto": 2.6, "radio": 0.6, "salto": 5.5, "color": Color(0.30, 0.28, 0.35), "puntos": 400,
		"empuje_golpe": 9.0, "modelo": "res://criaturas/bruto.glb"},
	# DATOS SACADOS DEL MODELO (clips de Blender a 30 fps). `amago`: s hasta el fotograma del golpe;
	# `recuperar`: lo que queda de clip tras el golpe, que andar no pisa (amago+recuperar < cadencia, para que
	# el siguiente ataque arranque el clip de cero). `vel_clip`: m/s a los que caminar y correr no patinan
	# (criatura.gd los reproduce a velocidad real / esa); `vel_correr`, entre las dos.
	# el ARRASTRADO va por el suelo tirando de medio cuerpo con los brazos: garras a 1,2 m, golpe a 0,40 s
	"arrastrado": {"nombre": "Arrastrado", "vida": 45.0, "velocidad": 2.6, "vel_correr": 1.5, "dano": 10.0, "alcance": 1.4,
		"cadencia": 0.9, "amago": 0.4, "recuperar": 0.45, "alto": 0.75, "radio": 0.45, "salto": 0.0,
		"color": Color(0.40, 0.45, 0.35), "puntos": 90, "modelo": "res://criaturas/arrastrado.glb",
		"vel_clip": {"caminar": 0.9, "correr": 2.5}},
	# el GORDO revienta al morir: mejor matarlo lejos. Muere hinchandose (clip de 2 s) y revienta al acabar
	"gordo": {"nombre": "Gordo", "vida": 260.0, "velocidad": 1.3, "vel_correr": 1.15, "dano": 20.0, "alcance": 1.6,
		"cadencia": 1.8, "amago": 0.5, "recuperar": 0.65, "alto": 2.1, "radio": 0.6, "salto": 4.0,
		"color": Color(0.50, 0.55, 0.35), "puntos": 250, "modelo": "res://criaturas/gordo.glb", "cadaver_s": 3.0,
		"vel_clip": {"caminar": 0.75, "correr": 1.74},
		"explosion": {"radio": 5.0, "dano": 70.0, "rompe": 2.0, "potencia": 110, "retraso": 0.6, "al_acabar_muerte": true},
		# EL VOMITO (Boomer): pantalla verde y la horda encima (2026-09-26)
		"ataques": [
			{"anim": "ataque", "alcance": 1.6, "dano": 20.0, "amago": 0.4, "recuperar": 0.4, "cadencia": 1.4},
			{"anim": "vomitar", "alcance": 4.5, "vomito": true, "necesita_vista": true, "bilis_s": 12.0, "horda": 6,
				"amago": 0.6, "cadencia": 12.0, "recuperar": 0.5}]},
	# el ESCUPIDOR ataca de lejos con acido si te ve, y de cerca con las garras (mano a 1,1 m, golpe a 0,40 s)
	"escupidor": {"nombre": "Escupidor", "vida": 110.0, "velocidad": 2.2, "vel_correr": 1.6, "dano": 12.0, "alcance": 1.3,
		"cadencia": 1.2, "amago": 0.4, "alto": 1.9, "radio": 0.35, "color": Color(0.35, 0.50, 0.25), "puntos": 200,
		"modelo": "res://criaturas/escupidor.glb", "vel_clip": {"caminar": 0.86, "correr": 3.0},
		"ataques": [
			{"anim": "ataque", "alcance": 1.3, "dano": 12.0, "amago": 0.4, "recuperar": 0.35, "cadencia": 1.2},
			# hincha el saco hasta 0,47 s y escupe a 0,60 s por la boca: 1,04 m al frente y 1,38 m de alto
			{"anim": "escupir", "alcance": 20.0, "min": 3.0, "proyectil": true, "vel": 16.0, "dano": 14.0,
				"amago": 0.6, "cadencia": 2.6, "recuperar": 0.43, "boca": Vector2(1.04, 1.38)}]},
	# el SALTADOR se te echa encima de un salto desde lejos (clip salto: despega a 0,2 s y cae a 0,70 s)
	"saltador": {"nombre": "Saltador", "vida": 80.0, "velocidad": 3.2, "vel_correr": 1.4, "dano": 14.0, "alcance": 1.5,
		"cadencia": 1.0, "amago": 0.3, "alto": 1.9, "radio": 0.33, "salto": 8.0, "color": Color(0.45, 0.35, 0.30),
		"puntos": 180, "modelo": "res://criaturas/saltador.glb", "vel_clip": {"caminar": 0.65, "correr": 3.0},
		"ataques": [
			{"anim": "ataque", "alcance": 1.5, "dano": 14.0, "amago": 0.3, "recuperar": 0.4, "cadencia": 1.0},
			{"anim": "salto", "alcance": 10.0, "min": 4.0, "salto_ataque": true, "dano": 22.0, "amago": 0.7,
				"cadencia": 4.0, "recuperar": 0.23}]},
	# el AULLADOR grita: enfurece a los de alrededor y llama a mas zombis. Hay que matarlo el primero
	"aullador": {"nombre": "Aullador", "vida": 70.0, "velocidad": 2.4, "vel_correr": 1.5, "dano": 8.0, "alcance": 1.4,
		"cadencia": 1.2, "amago": 0.33, "alto": 1.85, "radio": 0.30, "color": Color(0.55, 0.50, 0.45), "puntos": 300,
		"modelo": "res://criaturas/aullador.glb", "vel_clip": {"caminar": 0.6, "correr": 2.7},
		"ataques": [
			{"anim": "ataque", "alcance": 1.4, "dano": 8.0, "amago": 0.33, "recuperar": 0.4, "cadencia": 1.2},
			{"anim": "grito", "alcance": 25.0, "min": 6.0, "grito": true, "amago": 1.1, "cadencia": 10.0,
				"recuperar": 0.9, "invoca": ["zombi", "zombi"]}]},
	# la ARANA se levanta y muerde (golpe a 0,30 s)
	"arana": {"nombre": "Arana", "vida": 130.0, "velocidad": 3.6, "vel_correr": 1.2, "dano": 16.0, "alcance": 1.8,
		"cadencia": 1.0, "amago": 0.3, "recuperar": 0.45, "alto": 1.25, "radio": 0.6, "salto": 7.0,
		"color": Color(0.25, 0.22, 0.20), "puntos": 260, "modelo": "res://criaturas/arana.glb",
		"vel_clip": {"caminar": 0.55, "correr": 2.6}},
	# el ACORAZADO aguanta casi todo de frente: hay que rodearlo o volarlo (golpe de escudo a 0,53 s)
	"acorazado": {"nombre": "Acorazado", "vida": 380.0, "velocidad": 1.7, "vel_correr": 1.2, "dano": 28.0, "alcance": 2.0,
		"cadencia": 1.7, "amago": 0.53, "recuperar": 0.5, "alto": 2.2, "radio": 0.55, "color": Color(0.55, 0.52, 0.45),
		"puntos": 450, "modelo": "res://criaturas/acorazado.glb", "blindaje_frontal": 0.8, "empuje_golpe": 8.0,
		"vel_clip": {"caminar": 0.56, "correr": 1.8}},
	# EL JEFE TIENE QUE DAR MIEDO. Andando a 2,4 m/s no alcanzaba ni a un jugador caminando de espaldas:
	# le disparabas retrocediendo y se moria sin haberte tocado. Ahora CARGA a 6,5 m/s en cuanto te ve a
	# mas de 6 m, te SALTA ENCIMA desde media distancia (su clip de salto estaba hecho y sin usar), se
	# ENFURECE al 60 % y al 30 % de vida -ruge otra vez y no para de correr- y, si algo se le cruza, lo
	# tira abajo en vez de quedarse trabado.
	# ================ LOS ESPECIALES DE LEFT 4 DEAD 2 (2026-09-26, modelos en tools/blender/criaturas/especiales_l4d2.py)
	# CAZADOR (Hunter): salta de lejos, te tira al suelo y te desgarra. Se lo quitas de encima haciendole daño.
	"cazador": {"nombre": "Cazador", "vida": 250.0, "velocidad": 3.6, "vel_correr": 2.2, "dano": 8.0, "alcance": 1.4,
		"cadencia": 1.0, "amago": 0.3, "alto": 1.75, "radio": 0.33, "color": Color(0.26, 0.30, 0.38), "puntos": 350,
		"modelo": "res://criaturas/cazador.glb", "vel_clip": {"caminar": 0.64, "correr": 2.86},
		"agarre_dps": 10.0, "agarre_suelta": 60.0, "agarre_max": 9.0,
		"ataques": [
			{"anim": "ataque", "alcance": 1.4, "dano": 8.0, "amago": 0.3, "recuperar": 0.35, "cadencia": 1.0},
			{"anim": "salto", "alcance": 14.0, "min": 0.8, "salto_ataque": true, "agarre": "tirado", "dano": 10.0,
				"amago": 0.55, "cadencia": 4.0, "recuperar": 0.3}]},
	# FUMADOR (Smoker): te atrapa con la lengua desde lejos y te arrastra; al cortarle la vista, la suelta.
	"fumador": {"nombre": "Fumador", "vida": 250.0, "velocidad": 2.2, "vel_correr": 1.9, "dano": 8.0, "alcance": 1.4,
		"cadencia": 1.2, "amago": 0.35, "alto": 2.3, "radio": 0.33, "color": Color(0.48, 0.40, 0.30), "puntos": 350,
		"modelo": "res://criaturas/fumador.glb", "vel_clip": {"caminar": 0.79, "correr": 3.5},
		"agarre_dps": 6.0, "agarre_suelta": 45.0, "agarre_max": 10.0,
		"ataques": [
			{"anim": "ataque", "alcance": 1.4, "dano": 8.0, "amago": 0.35, "recuperar": 0.4, "cadencia": 1.2},
			{"anim": "lengua", "alcance": 20.0, "min": 3.0, "agarre": "lengua", "necesita_vista": true, "dano": 3.0,
				"amago": 0.4, "cadencia": 8.0, "recuperar": 0.2}]},
	# JINETE (Jockey): salta a tu espalda y te lleva a donde quiere.
	"jinete": {"nombre": "Jinete", "vida": 325.0, "velocidad": 4.0, "vel_correr": 2.0, "dano": 6.0, "alcance": 1.2,
		"cadencia": 0.9, "amago": 0.3, "alto": 1.35, "radio": 0.28, "color": Color(0.50, 0.46, 0.38), "puntos": 350,
		"modelo": "res://criaturas/jinete.glb", "vel_clip": {"caminar": 0.47, "correr": 2.1},
		"agarre_dps": 5.0, "agarre_suelta": 50.0, "agarre_max": 12.0, "sube_jinete": 0.95,
		"ataques": [
			{"anim": "ataque", "alcance": 1.2, "dano": 6.0, "amago": 0.3, "recuperar": 0.35, "cadencia": 0.9},
			{"anim": "salto", "alcance": 10.0, "min": 0.8, "salto_ataque": true, "agarre": "jinete", "dano": 4.0,
				"amago": 0.45, "cadencia": 4.0, "recuperar": 0.2}]},
	# CARGADOR (Charger): carga en linea recta, se lleva a uno por delante y lo machaca contra el suelo.
	"cargador": {"nombre": "Cargador", "vida": 600.0, "velocidad": 2.5, "vel_correr": 2.3, "dano": 15.0, "alcance": 1.7,
		"cadencia": 1.4, "amago": 0.4, "alto": 2.15, "radio": 0.45, "color": Color(0.30, 0.36, 0.50), "puntos": 500,
		"modelo": "res://criaturas/cargador.glb", "vel_clip": {"caminar": 0.73, "correr": 3.27}, "vel_carga": 8.5,
		"agarre_dps": 15.0, "agarre_suelta": 90.0, "agarre_max": 8.0,
		"ataques": [
			{"anim": "ataque", "alcance": 1.7, "dano": 15.0, "amago": 0.4, "recuperar": 0.45, "cadencia": 1.4, "empuje": 6.0},
			{"anim": "carga", "alcance": 18.0, "min": 5.0, "carga_ataque": true, "necesita_vista": true, "agarre": "cargado",
				"dano": 15.0, "empuje": 12.0, "dura": 2.0, "rompe": 1.3, "potencia": 230, "amago": 0.5, "cadencia": 10.0,
				"recuperar": 0.2}]},
	# TANQUE (Tank): puñetazos que mandan lejos, pedruscos, cargas que lo rompen todo, y te AHORCA hasta que le
	# hacen bastante daño.
	"tanque": {"nombre": "TANQUE", "vida": 2600.0, "velocidad": 3.2, "vel_correr": 2.6, "dano": 40.0, "alcance": 2.3,
		"cadencia": 1.6, "amago": 0.45, "alto": 2.6, "radio": 0.7, "color": Color(0.52, 0.56, 0.42), "puntos": 2500,
		"modelo": "res://criaturas/tanque.glb", "vel_clip": {"caminar": 0.9, "correr": 4.0}, "vel_carga": 9.0,
		"empuje_golpe": 12.0, "rugido_al_salir": true, "rugido_s": 2.2, "grande": true,
		"agarre_dps": 9.0, "agarre_suelta": 160.0, "agarre_max": 9.0,
		"romper": 1.6, "potencia_romper": 210,
		"ataques": [
			{"anim": "punetazo", "alcance": 2.4, "dano": 40.0, "empuje": 14.0, "amago": 0.45, "cadencia": 1.6, "recuperar": 0.5},
			{"anim": "agarrar", "alcance": 2.3, "agarre": "estrangulado", "dano": 5.0, "amago": 0.45, "cadencia": 12.0,
				"recuperar": 0.2},
			{"anim": "carga", "alcance": 16.0, "min": 6.0, "carga_ataque": true, "necesita_vista": true, "dano": 30.0,
				"empuje": 14.0, "dura": 1.6, "rompe": 1.8, "potencia": 240, "amago": 0.4, "cadencia": 9.0, "recuperar": 0.2},
			{"anim": "lanzar_roca", "alcance": 30.0, "min": 8.0, "lanza_bloque": true, "dano": 45.0, "amago": 1.1,
				"cadencia": 9.0, "bloque": 1.4, "rompe": 2.2, "potencia": 190, "vel": 18.0, "cava": 1.6, "recuperar": 0.6}]},
	# BRUJA (Witch): llora sentada. Si la molestas (cerca, tiros) se levanta y va a por quien la molesto.
	"bruja": {"nombre": "Bruja", "vida": 1000.0, "velocidad": 6.8, "vel_correr": 2.2, "dano": 90.0, "alcance": 1.6,
		"cadencia": 1.0, "amago": 0.3, "alto": 1.7, "radio": 0.3, "color": Color(0.86, 0.84, 0.80), "puntos": 1000,
		"modelo": "res://criaturas/bruja.glb", "vel_clip": {"caminar": 0.61, "correr": 2.73}, "bruja": true,
		"ataques": [
			{"anim": "zarpazo", "alcance": 1.6, "dano": 90.0, "empuje": 6.0, "amago": 0.3, "cadencia": 1.0, "recuperar": 0.3}]},
	"goliat": {"nombre": "GOLIAT", "vida": 6000.0, "velocidad": 2.4, "vel_carga": 6.5, "carga_min": 6.0,
		"vel_correr": 4.0, "dano": 60.0, "alcance": 4.5, "furia_vida": [0.6, 0.3],
		"cadencia": 2.4, "amago": 0.8, "alto": 6.5, "radio": 1.8, "salto": 0.0, "color": Color(0.22, 0.18, 0.16),
		"puntos": 5000, "jefe": true, "empuje_golpe": 16.0, "modelo": "res://criaturas/goliat.glb",
		"rugido_al_salir": true, "rugido_s": 3.0, "cadaver_s": 12.0,
		# ABRE PASO MUCHO MAS SEGUIDO (lo pidio el usuario, "ni se siente"): espera 0,75 s en vez de 1,2
		# antes de reventar lo que tiene delante, y puede repetir cada 0,5 s en vez de cada 0,8. Sale un
		# 60% mas de golpes por minuto.
		# 2026-09-18: mas grande y el doble de seguido (0,3 s), y rompe hacia el objetivo sin esperar a atascarse (criatura.gd)
		"romper": 2.6, "potencia_romper": 200, "romper_cada": 0.3, "bloqueo_romper": 0.4,
		"anims": {"correr": "carga", "dano": "dano", "muerte": "muerte"},
		"dano_fuerte": "dano_fuerte", "dano_fuerte_min": 220.0,
		# medidos en el propio clip (tools/blender/criaturas/goliat.py): a esta velocidad el pie apoyado
		# se queda quieto en el suelo. Antes eran a ojo (2,4 y 6,5) y el jefe andaba patinando.
		"vel_clip": {"caminar": 2.43, "correr": 6.17},
		# LOS ALCANCES DE CERCA ESTAN MEDIDOS (--goliatmira), no puestos a ojo: el brazo del Goliat da
		# 3 m desde el hombro, asi que pegando desde 4,5 la mano se quedaba en el aire por mucho que se
		# estirara. Ahora se acerca hasta donde llega de verdad y `mirar_bicho.gd` hace el resto.
		# NUEVE ATAQUES, para que no se le vea venir siempre lo mismo: dos zarpazos (uno por mano), el
		# doble zarpazo de cerca, mordisco, coletazo cuando lo tienes al lado, pisoton, golpe al suelo,
		# el salto -lo unico que alcanza de lejos, y lo que castiga retroceder disparando- y ARRANCAR UN
		# PEDAZO DE SUELO Y TIRARTELO, que rompe donde cae.
		"ataques": [
			{"anim": "zarpazo", "alcance": 3.4, "dano": 45.0, "amago": 0.55, "cadencia": 2.0, "empuje": 14.0, "recuperar": 0.8},
			{"anim": "zarpazo_izq", "alcance": 3.4, "dano": 45.0, "amago": 0.55, "cadencia": 2.0, "empuje": 14.0, "recuperar": 0.8},
			{"anim": "zarpazo_doble", "alcance": 3.0, "dano": 80.0, "amago": 0.75, "cadencia": 3.4, "empuje": 18.0,
				"recuperar": 1.0, "devora": true},
			{"anim": "mordisco", "alcance": 3.2, "dano": 70.0, "amago": 0.55, "cadencia": 2.2, "empuje": 6.0,
				"recuperar": 0.7, "devora": true},
			{"anim": "coletazo", "alcance": 5.5, "min": 2.0, "dano": 40.0, "amago": 0.72, "cadencia": 3.2,
				"area": 5.5, "empuje": 12.0, "recuperar": 0.8},
			{"anim": "pisoton", "alcance": 3.6, "dano": 50.0, "amago": 0.6, "cadencia": 2.6, "area": 3.2,
				"rompe": 1.6, "potencia": 120, "recuperar": 0.7},
			{"anim": "golpe_suelo", "alcance": 6.0, "dano": 55.0, "amago": 0.8, "cadencia": 3.0, "area": 5.0,
				"rompe": 2.6, "potencia": 140, "recuperar": 0.9},
			{"anim": "salto", "alcance": 22.0, "min": 6.5, "dano": 60.0, "amago": 0.78, "salto_ataque": true,
				"cadencia": 7.0, "recuperar": 0.9, "empuje": 16.0, "area": 4.5, "rompe": 2.0, "potencia": 120},
			{"anim": "arrancar", "alcance": 26.0, "min": 7.0, "dano": 65.0, "amago": 1.67, "cadencia": 8.0,
				# LA ROCA REVIENTA COMO EL MISIL (4 m, potencia 255). Lo pidio el usuario. Con 2,4 m y 190,
				# contra hormigon (170) solo alcanzaba 0,8 m -la fuerza cae con la distancia, ver
				# World::carveSphere-: al jugador subido a un tejado apenas le arañaba el suelo.
				"recuperar": 0.8, "lanza_bloque": true, "vel": 14.45, "bloque": 1.6, "rompe": 4.0,
				"potencia": 255, "cava": 2.0}]},
}

## Cada oleada presenta a alguien nuevo y mezcla lo ya visto; la 10 es la del jefe.
const OLEADAS := [
	[["zombi", 6]],
	[["zombi", 8], ["arrastrado", 3]],
	[["zombi", 8], ["corredor", 4], ["arrastrado", 2]],
	[["zombi", 8], ["corredor", 4], ["gordo", 2], ["escupidor", 1], ["cazador", 1]],
	[["zombi", 10], ["corredor", 5], ["bruto", 1], ["saltador", 2], ["fumador", 1]],
	[["zombi", 10], ["corredor", 5], ["escupidor", 2], ["arana", 2], ["aullador", 1], ["jinete", 1], ["cargador", 1]],
	[["zombi", 10], ["corredor", 6], ["gordo", 2], ["acorazado", 1], ["saltador", 3], ["cazador", 1], ["fumador", 1]],
	[["zombi", 12], ["corredor", 6], ["bruto", 2], ["arana", 3], ["escupidor", 2], ["aullador", 1], ["cargador", 1], ["jinete", 2]],
	[["zombi", 12], ["corredor", 8], ["acorazado", 2], ["bruto", 2], ["saltador", 3], ["gordo", 2], ["arrastrado", 3], ["tanque", 1], ["fumador", 1]],
	# LA 10 ES EL JEFE Y NADA MAS. Traia ademas veinte bichos (diez zombis, seis corredores, dos aranas y
	# dos escupidores) y el Goliat se perdia entre la multitud. Lo pidio el usuario. El Goliat no invoca
	# a nadie -eso solo lo hace el aullador-, asi que en esta oleada no sale otra cosa.
	[["goliat", 1]],
]

var jugador: Node3D = null
var world = null
var hud = null
var contenedor: Node3D = null
var oleada := 0
var puntos := 0
var bajas := 0
var terminado := false
var _fin_vigia := 0.0
var _fin_pide := 0.0
var _quedan_red := -1
var _cola: Array = []
var _vivos: Array = []
var _salir_t := 0.0
var _descanso_t := 5.0


func setup(p_jugador: Node3D, p_world, p_hud, p_contenedor: Node3D) -> void:
	jugador = p_jugador
	world = p_world
	hud = p_hud
	contenedor = p_contenedor
	_mensaje("MODO PvE · aguanta %d oleadas" % OLEADAS.size())
	if not Net.criatura_agarra.is_connected(_agarre_de_red):
		Net.criatura_agarra.connect(_agarre_de_red)
	if not Net.bilis_para_mi.is_connected(_bilis_de_red):
		Net.bilis_para_mi.connect(_bilis_de_red)
	if "--animbotstest" in OS.get_cmdline_user_args():
		prueba_anim_bots.call_deferred()
	if "--medirfps" in OS.get_cmdline_user_args():
		var mf: Node = load("res://scripts/medidor_fps.gd").new()
		mf.name = "MedidorFps"
		add_child(mf)
	for _cb in OS.get_cmdline_user_args():
		if String(_cb).begins_with("--cazabot"):
			_cazabot.call_deferred(String(_cb).substr(10) if String(_cb).contains("=") else "cazador")
	if "--lenguatest" in OS.get_cmdline_user_args():
		prueba_lengua.call_deferred()
	if "--especialestest" in OS.get_cmdline_user_args():
		prueba_especiales.call_deferred()
	if "--agarrebotstest" in OS.get_cmdline_user_args():
		_agarre_bots_prueba.call_deferred()
	if "--agarrelan" in OS.get_cmdline_user_args():
		_agarre_lan.call_deferred()
	if "--aliadostest" in OS.get_cmdline_user_args():
		prueba_aliados.call_deferred()
	if "--aliadoslan" in OS.get_cmdline_user_args():
		_aliados_lan.call_deferred()
	_cargar_pistas()
	if "--tocapve" in OS.get_cmdline_user_args():
		_toca_test()
	# PRUEBA --pveoleada=N: empieza directamente en esa oleada, deja 30 s de pelea y cuenta lo que han
	# hecho las criaturas (escupir, gritar, saltar, reventar). Para probar los bichos sin jugar diez oleadas.
	# --pvediag solo: el flujo normal (el del lobby) con los [pvediag] cada 5 s.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pveoleada="):
			oleada = clampi(int(a.substr(12)) - 1, 0, OLEADAS.size() - 1)
			_descanso_t = 0.5
			_prueba_t = 30.0
			_diag = true
		elif a.begins_with("--jugaroleada="):
			# JUGAR DESDE ESA OLEADA, de verdad (2026-09-23): --pveoleada es una PRUEBA -te mantiene la vida a 100 y
			# a los 20 s mata ella misma a los bichos-, y probando al jefe salia VICTORIA sin hacer nada. Esta solo
			# salta la oleada: se pelea, se muere y te come el Goliat como en la partida normal.
			oleada = clampi(int(a.substr(14)) - 1, 0, OLEADAS.size() - 1)
		elif a == "--pvediag":
			_diag = true
	CriaturaScript.diag = _diag
	if Net != null and Net.is_online() and Net.hosting:
		if not Net.piden_censo_criaturas.is_connected(_mandar_censo_criaturas):
			Net.piden_censo_criaturas.connect(_mandar_censo_criaturas)
	# EL RELEVO DEL ANFITRION TAMBIEN ES COSA MIA. Sin esto, al irse el anfitrion el que tomaba el mando
	# de la red seguia aqui dentro creyendose invitado: criaturas sin cerebro, ninguna oleada y nadie
	# repartiendo el censo. El usuario: "si el host se va no pasa a ser host otro jugador, el juego
	# quedo roto, no funcionaba nada".
	if Net != null and not Net.migrando.is_connected(_al_migrar):
		Net.migrando.connect(_al_migrar)
	# los botiquines son del mundo: los ve y los recoge cualquiera, sea anfitrion o invitado
	if Net != null and not Net.botiquines_nuevos.is_connected(_red_botiquines):
		Net.botiquines_nuevos.connect(_red_botiquines)
	if Net != null and not Net.botiquin_recogido.is_connected(_red_botiquin_recogido):
		Net.botiquin_recogido.connect(_red_botiquin_recogido)
	# el final de la partida lo decide el anfitrion, pero la pantalla la abre cada uno
	if Net != null and not Net.fin_pve_red.is_connected(_red_fin):
		Net.fin_pve_red.connect(_red_fin)
	# REVIVIR ES DE TODOS, TAMBIEN DEL ANFITRION. Esto estaba conectado SOLO en la rama del invitado,
	# y esa rama sale de `setup` con un `return`: el que hacia de anfitrion moria, se quedaba de
	# espectador y al superar la oleada no volvia NUNCA, porque el aviso lo emitia el mismo y no habia
	# nadie escuchando en su propia maquina. Lo conto el usuario: "hay un error al terminar la horda,
	# no respawnea, sigue espectando".
	if Net != null and not Net.revivir_todos.is_connected(_revivir_caidos):
		Net.revivir_todos.connect(_revivir_caidos)
	# LAS PRUEBAS NO TIENEN DEDOS: sin nadie que pulse EMPEZAR se quedarian mirando el panel para siempre.
	var linea := " ".join(OS.get_cmdline_user_args())
	_auto = (linea.contains("--pveoleada=") or linea.contains("--pvetest") or linea.contains("--pvesolo=")
		or linea.contains("--lanzombis") or linea.contains("--zombicadaver") or linea.contains("--zurranalmuerto") or linea.contains("--tirozombi") or linea.contains("--cadavercae") or linea.contains("--migrapve"))
	# EN LAN MANDA EL ANFITRION. El lleva las oleadas, la inteligencia y la vida de los bichos; los
	# invitados no piensan nada: reciben donde esta cada uno y lo dibujan. Asi todos ven lo mismo.
	_en_red = Net != null and Net.is_online()
	_soy_host = not _en_red or Net.hosting
	# LA PALANCA DEL JEFE, SOLO JUGANDO SOLO. Se quito de en medio porque teniendola delante nadie
	# jugaba las nueve oleadas; pero sin internet y sin nadie mas, es la unica forma de ir a por el
	# Goliat sin pasarte diez minutos antes. En partida con otros NO sale: saltarse las oleadas seria
	# saltarselas para todos.
	if not _en_red and not PUESTOS.any(func(d): return String(d["id"]) == "jefe"):
		PUESTOS.append(PUESTO_JEFE)
	if _en_red and not _soy_host:
		Net.criatura_nueva.connect(_red_nueva)
		Net.criatura_estado.connect(_red_estado)
		Net.roca_arrancada.connect(_red_roca)
		Net.criatura_muerta.connect(_red_muerta)
		Net.oleada_estado.connect(_red_oleada)
		# LOS PUESTOS TAMBIEN SON DE TODOS. Antes solo los veia el anfitrion y el invitado se quedaba
		# sin boton y sin tienda: no podia ni empezar la oleada ni comprar.
		Net.puestos_sitio.connect(_red_puestos_sitio)
		Net.estado_pve.connect(_red_estado_pve)
		Net.alarma_oleada.connect(_red_alarma)
		Net.aviso_pve.connect(func(t: String): _mensaje(t))
		Net.compra_concedida.connect(_aplicar_compra)
		# YA ESTOY LISTO: que me cuenten que bichos hay. Lo pide el que llega, no lo adivina el
		# anfitrion, porque hasta este momento no habia nadie escuchando al otro lado.
		Net.pedir_censo_criaturas()
		_objetivo("MODO ZOMBIS · manda el anfitrion")
		return
	_montar_puestos()
	_mostrar_puestos(true)
	_mandar_puestos()
	print("[pve] empieza en %s · %d pistas de salida · puestos %s" % [_mapa(), _pistas.size(), str(PUESTOS.map(func(d): return d["id"]))])


# ---------------------------------------------------------------------------
# ENTRE OLEADAS MANDAS TU. Al entrar no pasa nada: te colocas, miras el sitio y empiezas cuando
# quieras. En el centro hay dos botones -EMPEZAR OLEADA y TIENDA- que se van deslizandose al empezar y
# vuelven al acabar. La tienda se paga con el ORO que sueltan los bichos al morir.
# ---------------------------------------------------------------------------
const ORO_POR_PUNTO := 0.1          ## un zombi (100 puntos) deja 10 de oro
const TIENDA := [
	{"id": "armadura", "nombre": "ARMADURA", "precio": 300,
		"texto": "Chaleco completo: se come dos tercios de cada golpe hasta que se rompe.",
		"color": Color(0.35, 0.70, 1.0)},
	{"id": "botiquin", "nombre": "BOTIQUIN", "precio": 250,
		"texto": "Suelta cuatro botiquines en el suelo: pisar uno te deja la vida al maximo.",
		"color": Color(0.92, 0.30, 0.30)},
	{"id": "laser", "nombre": "FUSIL LASER", "precio": 900,
		"texto": "El fusil de energia: no tiene retroceso y atraviesa lo que le pongas delante.",
		"color": Color(0.45, 0.95, 1.0)},
	{"id": "municion", "nombre": "MUNICION", "precio": 150,
		"texto": "Cargadores llenos y la reserva al tope, de todas las armas.",
		"color": Color(0.95, 0.72, 0.12)},
]
const BotiquinSuelto := preload("res://scripts/botiquin_suelto.gd")
const ALARMA := "res://sounds/pve/alarma_oleada.mp3"
const ALARMA_S := 15.0              ## lo que suena de la sirena
const ALARMA_FIN := 2.5             ## y lo que tarda en apagarse, para que no se corte de golpe
## LOS PUESTOS SON COSAS DEL MAPA, no una pantalla: te acercas, los miras y los usas con [E] (o con el
## boton USAR en el movil). Salen del suelo al acabar una oleada y se hunden al empezar la siguiente.
## Son dos: el pulsador rojo de empezar y la maquina de la tienda (que abre su ventana con todo
## dentro).
##
## LA PALANCA DE SALTAR AL JEFE SE QUITO DEL JUEGO. Era un atajo a la oleada 10 y se cargaba el modo:
## teniendola ahi delante, la partida de verdad -las nueve oleadas, ir comprando, llegar al Goliat con
## lo que hayas juntado- se convertia en algo opcional que nadie jugaba. El salto sigue existiendo por
## linea de comandos (--pveoleada=10) para poder PROBAR al jefe sin jugar diez oleadas.
## LA PALANCA DEL JEFE (salta directo a la oleada 10) SALE SOLO JUGANDO SOLO, sin sala. Fue un boton de
## prueba, se quito de la partida con otros porque se cargaba el modo -teniendola delante, jugar las
## nueve oleadas era opcional- y volvio para el que juega sin internet, que si no tiene forma de ver al
## Goliat sin pasarse diez minutos (ver `_ready`). Esto la fuerza tambien en red, y --palancajefe igual.
const MOSTRAR_PALANCA_JEFE := false
const PUESTO_JEFE := {"id": "jefe", "nombre": "OLEADA 10 · JEFE", "color": Color(0.95, 0.45, 0.10)}
var PUESTOS: Array = [
	{"id": "empezar", "nombre": "EMPEZAR OLEADA", "color": Color(0.95, 0.12, 0.10)},
	{"id": "tienda", "nombre": "TIENDA", "color": Color(0.95, 0.72, 0.12)},
] + ([PUESTO_JEFE] if (MOSTRAR_PALANCA_JEFE or "--palancajefe" in OS.get_cmdline_user_args()) else [])
## Lo que te dan al saltar directo al jefe. Te has perdido nueve oleadas de cobrar, asi que llegarias
## con la pistola y sin nada que comprar: sin esto el boton no serviria para pelear con el, solo para
## morirse rapido. Solo rellena hasta ahi; si ya llevas mas, no te quita nada.
const ORO_SALTO_JEFE := 2500
const TiendaPve := preload("res://scripts/tienda_pve.gd")
## A QUE DISTANCIA SE USA UN PUESTO. En movil se usa desde mas lejos y sin tener que clavarle la vista:
## con el dedo no se apunta fino y uno se queda dando vueltas al lado del puesto sin que salga nada.
const ALCANCE_USO := 2.8
const ALCANCE_USO_TACTIL := 4.5
const HUNDE := 2.2                  ## lo que se meten bajo tierra mientras dura la oleada
var oro := 0
var _esperando := true
var _auto := false                  ## en las pruebas no hay quien pulse: arranca sola
var _puestos: Array = []            ## [{id, nodo, y}]
var _puestos_fuera := false
var _en_red := false
var _soy_host := true
var _prox_id := 1                   ## numero de cada criatura, el mismo en todas las maquinas
var _red_t := 0.0                   ## reloj del envio de posiciones
var _estado_t := 0.0                ## reloj del envio de oleada/oro/puestos
var _repite_sitio := 0
var _remotas: Dictionary = {}       ## invitados: red_id -> criatura que solo se dibuja
var _mirado := ""                   ## puesto que el jugador tiene delante ahora mismo
var _alarma: AudioStreamPlayer = null
var _alarma_sonada := false
var _alarma_t := 0.0                ## lo que queda de sirena antes de que salga la primera oleada


## Los tres puestos salen del suelo delante de donde apareces, mirando hacia ti.
func _montar_puestos() -> void:
	add_to_group("puestos_pve")     # el botón USAR de móvil llega por aquí
	Minimapa.quitar_sitio("pve_boton")   # las marcas del minimapa son estaticas: sobreviven a la partida
	_alarma = AudioStreamPlayer.new()
	if ResourceLoader.exists(ALARMA):
		_alarma.stream = load(ALARMA)
	add_child(_alarma)
	if not is_instance_valid(jugador) or world == null:
		return
	var base: Vector3 = jugador.global_position
	var adelante: Vector3 = -jugador.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length() > 0.05 else Vector3.FORWARD
	var lado: Vector3 = adelante.cross(Vector3.UP).normalized()
	for i in PUESTOS.size():
		var d: Dictionary = PUESTOS[i]
		# centrados delante de ti sean dos o tres: con el desplazamiento fijo de dos, al anadir el
		# tercero todo el conjunto se iba de lado y el de la punta te quedaba a la espalda
		var p: Vector3 = base + adelante * 3.4 + lado * ((float(i) - (PUESTOS.size() - 1) * 0.5) * 2.6)
		var h: Dictionary = world.raycast(p + Vector3.UP * 3.0, Vector3.DOWN, 9.0)
		p.y = (h["position"] as Vector3).y if h.get("hit", false) else base.y
		var n := _hacer_puesto(d)
		add_child(n)
		n.global_position = p - Vector3(0.0, HUNDE, 0.0)      # empiezan hundidos: salen al mostrarlos
		n.look_at(Vector3(base.x, n.global_position.y, base.z), Vector3.UP)
		_puestos.append({"id": String(d["id"]), "nodo": n, "y": p.y})


func _hacer_puesto(d: Dictionary) -> Node3D:
	match String(d["id"]):
		"empezar": return _modelo_boton()
		"jefe": return _modelo_jefe()
		_: return _modelo_tienda()


## LA PALANCA DEL JEFE. Una columna de peligro (negro y ambar) con una palanca roja bajo una jaula:
## se ve desde lejos que eso NO es el boton de empezar, y la jaula dice sola que lo que hay debajo no
## se toca sin querer. Es lo que se salta lo que quede y saca al GOLIAT.
func _modelo_jefe() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Puesto_jefe"
	var negro := Color(0.09, 0.09, 0.10)
	var ambar := Color(0.98, 0.62, 0.05)
	raiz.add_child(_cilindro(0.46, 0.56, 0.09, Vector3(0, 0.045, 0), negro.lightened(0.05), 0.0, 0.6, 0.5))
	raiz.add_child(_bloque(Vector3(0.34, 1.12, 0.28), Vector3(0, 0.64, 0), negro, 0.0))
	# franjas de peligro: la columna se lee de lejos aunque no se lean los carteles
	for i in 6:
		raiz.add_child(_bloque(Vector3(0.35, 0.07, 0.29), Vector3(0, 0.24 + i * 0.17, 0), ambar, 0.12))
	# consola inclinada con la placa y la palanca
	var consola := _bloque(Vector3(0.46, 0.12, 0.38), Vector3(0, 1.26, 0.02), negro.lightened(0.10), 0.0)
	consola.rotation_degrees = Vector3(-16, 0, 0)
	raiz.add_child(consola)
	raiz.add_child(_bloque(Vector3(0.34, 0.025, 0.15), Vector3(0, 1.33, -0.12), ambar, 0.6))
	# la palanca: base, brazo inclinado y pomo rojo
	raiz.add_child(_cilindro(0.07, 0.08, 0.05, Vector3(0, 1.34, 0.07), Color(0.55, 0.56, 0.60), 0.0, 0.9, 0.25))
	var brazo := _bloque(Vector3(0.04, 0.24, 0.04), Vector3(0, 1.46, 0.12), Color(0.62, 0.63, 0.66), 0.0)
	brazo.rotation_degrees = Vector3(-26, 0, 0)
	raiz.add_child(brazo)
	var pomo := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.065
	sm.height = 0.13
	pomo.mesh = sm
	pomo.position = Vector3(0, 1.58, 0.18)
	pomo.material_override = _mat(Color(0.95, 0.10, 0.08), 0.9, 0.0, 0.35)
	raiz.add_child(pomo)
	# la jaula: dos arcos de barra por encima, para que se lea "esto no se toca sin querer"
	for x in [-0.18, 0.18]:
		raiz.add_child(_bloque(Vector3(0.028, 0.40, 0.028), Vector3(x, 1.50, -0.08), Color(0.72, 0.74, 0.78), 0.0))
		raiz.add_child(_bloque(Vector3(0.028, 0.028, 0.42), Vector3(x, 1.70, 0.12), Color(0.72, 0.74, 0.78), 0.0))
	raiz.add_child(_bloque(Vector3(0.39, 0.028, 0.028), Vector3(0, 1.70, -0.09), Color(0.72, 0.74, 0.78), 0.0))
	# el piloto de arriba, latiendo: de noche es lo que canta desde lejos
	var piloto := _cilindro(0.06, 0.06, 0.09, Vector3(0, 1.80, -0.09), ambar, 2.4, 0.0, 0.3)
	raiz.add_child(piloto)
	var luz := OmniLight3D.new()
	luz.light_color = ambar
	luz.light_energy = 2.0
	luz.omni_range = 7.0
	luz.shadow_enabled = false
	luz.position = Vector3(0, 1.55, -0.2)
	raiz.add_child(luz)
	var tw := luz.create_tween().set_loops()
	tw.tween_property(luz, "light_energy", 0.7, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(luz, "light_energy", 2.3, 1.1).set_trans(Tween.TRANS_SINE)
	raiz.add_child(_cartel("OLEADA 10", Vector3(0, 2.12, 0), ambar, 0.17))
	raiz.add_child(_cartel("EL GOLIAT", Vector3(0, 1.96, 0), Color(0.95, 0.22, 0.16), 0.15))
	return raiz


## EL PULSADOR DE EMERGENCIA. Pie de chapa con banda de peligro, carcasa de metal, aro cromado y la
## seta roja encima, que se hunde al pulsarla. La luz de encima late despacio para que se vea de lejos.
func _modelo_boton() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Puesto_empezar"
	var metal := Color(0.13, 0.14, 0.16)
	var rojo := Color(0.95, 0.09, 0.07)
	raiz.add_child(_cilindro(0.46, 0.56, 0.08, Vector3(0, 0.04, 0), metal.darkened(0.3), 0.0, 0.6, 0.45))
	raiz.add_child(_cilindro(0.19, 0.24, 0.86, Vector3(0, 0.51, 0), metal, 0.0, 0.8, 0.35))
	# banda de peligro: la raya amarilla de las maquinas, a la altura de la mano
	raiz.add_child(_cilindro(0.21, 0.21, 0.07, Vector3(0, 0.72, 0), Color(0.95, 0.75, 0.05), 0.35, 0.2, 0.6))
	# cabezal: plato de chapa, aro cromado y, dentro, la seta
	raiz.add_child(_cilindro(0.42, 0.30, 0.10, Vector3(0, 0.99, 0), metal.lightened(0.08), 0.0, 0.85, 0.3))
	raiz.add_child(_cilindro(0.40, 0.42, 0.05, Vector3(0, 1.06, 0), Color(0.10, 0.10, 0.11), 0.0, 0.9, 0.25))
	var aro := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.30
	tm.outer_radius = 0.40
	tm.rings = 28
	aro.mesh = tm
	aro.position = Vector3(0, 1.08, 0)
	aro.material_override = _mat(Color(0.78, 0.80, 0.84), 0.0, 1.0, 0.12)
	raiz.add_child(aro)

	# la seta: es un nodo aparte porque al pulsar baja y sube
	var seta := Node3D.new()
	seta.name = "Seta"
	seta.position = Vector3(0, 1.09, 0)
	raiz.add_child(seta)
	var domo := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.31
	sm.height = 0.62
	sm.radial_segments = 32
	sm.rings = 16
	sm.is_hemisphere = true
	domo.mesh = sm
	domo.scale = Vector3(1.0, 0.66, 1.0)
	domo.position = Vector3(0, 0.04, 0)
	domo.material_override = _mat(rojo, 1.1, 0.1, 0.28)
	seta.add_child(domo)
	seta.add_child(_cilindro(0.31, 0.31, 0.09, Vector3(0, 0.02, 0), rojo.darkened(0.25), 0.5, 0.2, 0.4))

	var luz := OmniLight3D.new()
	luz.light_color = rojo
	luz.light_energy = 2.0
	luz.omni_range = 7.0
	luz.shadow_enabled = false
	luz.position = Vector3(0, 1.35, 0)
	raiz.add_child(luz)
	var tw := luz.create_tween().set_loops()
	tw.tween_property(luz, "light_energy", 0.6, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(luz, "light_energy", 2.2, 0.9).set_trans(Tween.TRANS_SINE)

	raiz.add_child(_cartel("EMPEZAR OLEADA", Vector3(0, 1.62, 0), rojo, 0.16))
	return raiz


## LA MAQUINA DE LA TIENDA. Un armario con su pantalla encendida, su bandeja y su rotulo; al usarla
## se abre la ventana con los articulos.
func _modelo_tienda() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Puesto_tienda"
	var metal := Color(0.12, 0.13, 0.15)
	var ambar := Color(0.98, 0.74, 0.16)
	raiz.add_child(_bloque(Vector3(1.24, 0.12, 0.80), Vector3(0, 0.06, 0), metal.darkened(0.35), 0.0))
	raiz.add_child(_bloque(Vector3(1.10, 1.95, 0.62), Vector3(0, 1.05, 0), metal, 0.0))
	# costillas laterales: rompen el ladrillo liso y le dan aire de maquina
	for s in [-1.0, 1.0]:
		raiz.add_child(_bloque(Vector3(0.10, 1.95, 0.70), Vector3(0.56 * s, 1.05, 0.0), metal.lightened(0.18), 0.0))
	raiz.add_child(_bloque(Vector3(1.26, 0.12, 0.72), Vector3(0, 2.07, 0), metal.lightened(0.12), 0.0))
	# pantalla: marco oscuro, cristal azulado y las lineas de la lista encendidas encima
	raiz.add_child(_bloque(Vector3(0.96, 0.96, 0.04), Vector3(0, 1.52, -0.32), Color(0.04, 0.05, 0.07), 0.0))
	raiz.add_child(_bloque(Vector3(0.88, 0.88, 0.03), Vector3(0, 1.52, -0.34), Color(0.05, 0.10, 0.16), 0.5))
	raiz.add_child(_bloque(Vector3(0.88, 0.05, 0.02), Vector3(0, 1.84, -0.35), ambar, 2.0))
	var y := 1.68
	for x in TIENDA:
		raiz.add_child(_cartel("%s  ◈%d" % [String(x["nombre"]), int(x["precio"])],
			Vector3(0, y, -0.36), x.get("color", ambar), 0.072))
		y -= 0.21
	raiz.add_child(_cartel("PULSA PARA ABRIR", Vector3(0, 1.16, -0.36), Color(0.62, 0.80, 0.92), 0.055))
	# bandeja de recogida y tirador
	raiz.add_child(_bloque(Vector3(0.80, 0.30, 0.06), Vector3(0, 0.58, -0.32), Color(0.05, 0.055, 0.07), 0.0))
	raiz.add_child(_bloque(Vector3(0.84, 0.06, 0.10), Vector3(0, 0.76, -0.33), metal.lightened(0.2), 0.0))
	raiz.add_child(_bloque(Vector3(1.04, 0.05, 0.03), Vector3(0, 1.97, -0.32), ambar, 2.2))
	raiz.add_child(_bloque(Vector3(1.04, 0.04, 0.03), Vector3(0, 0.22, -0.32), ambar, 1.6))

	var luz := OmniLight3D.new()
	luz.light_color = ambar
	luz.light_energy = 1.6
	luz.omni_range = 7.0
	luz.shadow_enabled = false
	luz.position = Vector3(0, 1.6, -0.5)
	raiz.add_child(luz)

	raiz.add_child(_cartel("TIENDA", Vector3(0, 2.30, 0), ambar, 0.20))
	return raiz


## Rotulo legible de lejos: mira al jugador porque el puesto entero ya esta girado hacia el.
func _cartel(t: String, pos: Vector3, col: Color, tam: float) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.rotation_degrees = Vector3(0, 180, 0)     # el puesto mira con -Z al jugador
	l.pixel_size = tam * 0.01
	l.font_size = 96
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.no_depth_test = false
	return l


func _mat(col: Color, brillo: float, metalico: float, aspereza: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metalico
	m.roughness = aspereza
	if brillo > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = brillo
	return m


func _cilindro(r_arriba: float, r_abajo: float, alto: float, pos: Vector3, col: Color,
		brillo: float, metalico: float, aspereza: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_arriba
	cm.bottom_radius = r_abajo
	cm.height = alto
	cm.radial_segments = 28
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(col, brillo, metalico, aspereza)
	return mi


func _bloque(tam: Vector3, pos: Vector3, col: Color, brillo: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(col, brillo, 0.35 if brillo <= 0.0 else 0.0, 0.55)
	return mi


## Salen del suelo al acabar una oleada y se hunden al empezar la siguiente.
func _mostrar_puestos(on: bool) -> void:
	if _puestos.is_empty() or _auto:
		return
	_puestos_fuera = on
	if not on and is_instance_valid(_ventana):
		_ventana.cerrar_ventana()      # empieza la oleada: la tienda se cierra sola
	if not on:
		_boton_tactil(false)
	_marcar_boton(on)
	for p in _puestos:
		var n: Node3D = p["nodo"]
		if not is_instance_valid(n):
			continue
		var tw := create_tween()
		tw.tween_property(n, "global_position:y", float(p["y"]) - (0.0 if on else HUNDE), 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## DONDE ESTABA EL BOTON. Mientras el puesto rojo esta fuera se marca con un circulito rojo pegado a
## el: si lo pierdes de vista, el circulo se queda en el borde de la pantalla con su flecha, y ademas
## sale un punto en el minimapa. Al empezar la oleada el puesto se hunde y la marca desaparece.
const ROJO_BOTON := Color(0.95, 0.17, 0.13)

func _marcar_boton(on: bool) -> void:
	var p: Vector3 = Vector3.ZERO
	for x in _puestos:
		if String(x["id"]) == "empezar" and is_instance_valid(x["nodo"]):
			p = (x["nodo"] as Node3D).global_position
	if not on or p == Vector3.ZERO:
		Minimapa.quitar_sitio("pve_boton")
		if hud and hud.has_method("quitar_objetivo_mundo"):
			hud.quitar_objetivo_mundo()
		return
	Minimapa.marcar_sitio("pve_boton", p, ROJO_BOTON)
	if hud and hud.has_method("set_objetivo_mundo"):
		hud.set_objetivo_mundo(p + Vector3.UP * 1.6, "EMPEZAR OLEADA", -1.0, ROJO_BOTON)


## El puesto que estas mirando de cerca: sale el cartel y, si pulsas, se usa.
func _usar_puestos() -> void:
	if is_instance_valid(_ventana):
		_mirado = ""
		_boton_tactil(false)
		return
	if not _puestos_fuera or not is_instance_valid(jugador):
		_boton_tactil(false)
		return
	var cam := jugador.get_viewport().get_camera_3d() if jugador.is_inside_tree() else null
	var tactil: bool = Settings.is_touch()
	var elegido := {}
	var mejor: float = ALCANCE_USO_TACTIL if tactil else ALCANCE_USO
	for p in _puestos:
		var n: Node3D = p["nodo"]
		if not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(jugador.global_position)
		if d > mejor:
			continue
		if cam and (n.global_position + Vector3.UP * 1.2 - cam.global_position).normalized() \
				.dot(-cam.global_transform.basis.z) < (0.30 if tactil else 0.72):
			continue                       # esta cerca pero le das la espalda
		mejor = d
		elegido = p
	if elegido.is_empty():
		_mirado = ""
		_boton_tactil(false)
		return
	var id := String(elegido["id"])
	_mirado = id
	# SIN TEXTO (pedido): un boton cuadrado con dibujo encima del puesto, como los del rescate
	_boton_tactil(true, id, (elegido["nodo"] as Node3D).global_position + Vector3.UP * 1.1, cam)
	if Input.is_action_just_pressed("interact"):
		usar_desde_jugador()


## Lo llama el jugador al interactuar: en móvil el botón USAR entra por aquí.
func usar_desde_jugador() -> void:
	if _mirado == "" or is_instance_valid(_ventana):
		return
	if _mirado == "empezar":
		_pulsar_boton()
		if _en_red and not _soy_host:
			Net.net_empezar_oleada()    # la oleada la arranca el anfitrion, que es quien la lleva
		else:
			empezar_ya()
	elif _mirado == "jefe":
		# LA OLEADA DEL JEFE, YA. Igual que empezar, pero diciendo a que oleada se salta. En red lo
		# pide al anfitrion: las oleadas las lleva el, y si cada uno saltara por su cuenta acabariamos
		# con dos partidas distintas.
		if _en_red and not _soy_host:
			Net.net_empezar_oleada(OLEADAS.size())
		else:
			empezar_ya(OLEADAS.size())
	else:
		_abrir_tienda()


## La seta roja se hunde y vuelve: se nota que la has pulsado.
func _pulsar_boton() -> void:
	for p in _puestos:
		if String(p["id"]) != "empezar":
			continue
		var n: Node3D = p["nodo"]
		if not is_instance_valid(n):
			continue
		var seta := n.get_node_or_null("Seta") as Node3D
		if seta == null:
			continue
		var tw := seta.create_tween()
		tw.tween_property(seta, "position:y", 1.02, 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(seta, "position:y", 1.09, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# LA TIENDA ES UNA VENTANA. La maquina esta en el mapa, pero al usarla se abre la pantalla con todo
# ordenado. Mientras esta abierta no se dispara: en escritorio sale el raton y en movil se esconden
# los mandos tactiles, que si no quedan por encima de los botones de comprar.
# ---------------------------------------------------------------------------
var _ventana: Control = null
var _raton_antes := Input.MOUSE_MODE_CAPTURED

func _abrir_tienda() -> void:
	if is_instance_valid(_ventana) or hud == null:
		return
	var v: Control = TiendaPve.new()
	v.oro = oro
	v.articulos = TIENDA
	hud.add_child(v)
	_ventana = v
	v.comprado.connect(func(id: String):
		_comprar(id)
		if is_instance_valid(_ventana):
			_ventana.poner_oro(oro))
	v.cerrado.connect(_cerrar_tienda)
	_raton_antes = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_boton_tactil(false)
	if "mobile" in hud and is_instance_valid(hud.mobile):
		hud.mobile.visible = false


func _cerrar_tienda() -> void:
	_ventana = null
	if not Settings.is_touch():
		Input.mouse_mode = _raton_antes
	if hud and "mobile" in hud and is_instance_valid(hud.mobile):
		hud.mobile.visible = true


## EN EL MOVIL NO HAY TECLA E. Cuando tienes un puesto delante sale este boton grande en pantalla, al
## margen de como tenga el jugador colocados sus mandos tactiles (puede haber quitado el de USAR).
var _btn: Button = null

const TouchIcons := preload("res://scripts/touch_icons.gd")

func _boton_tactil(on: bool, id := "", donde := Vector3.ZERO, cam: Camera3D = null) -> void:
	if hud == null:
		return
	var tactil := Settings.is_touch()
	if _btn == null or not is_instance_valid(_btn):
		if not on:
			return
		_btn = Button.new()
		_btn.focus_mode = Control.FOCUS_NONE
		_btn.mouse_filter = Control.MOUSE_FILTER_STOP if tactil else Control.MOUSE_FILTER_IGNORE
		_btn.custom_minimum_size = Vector2(84, 84)
		_btn.size = Vector2(84, 84)
		_btn.expand_icon = true
		_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_btn.add_theme_constant_override("icon_max_width", 60)
		var col := Color(1.0, 0.83, 0.0)
		for n in ["icon_normal_color", "icon_hover_color"]:
			_btn.add_theme_color_override(n, col)
		_btn.add_theme_color_override("icon_pressed_color", Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.055, 0.07, 0.72)
		sb.border_color = Color(col.r, col.g, col.b, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.set_content_margin_all(10)
		for st in ["normal", "hover", "focus", "pressed"]:
			_btn.add_theme_stylebox_override(st, sb)
		# (SIN LETRAS DE TECLAS (2026-10-04, pedido: "el juego es para el movil: ninguna letra de W A S D ni apretar E, el simbolo"): sin la E de la esquina)
		_btn.pressed.connect(usar_desde_jugador)
		hud.add_child(_btn)
		preload("res://scripts/teclas_pc.gd").marca(_btn, "F")
	if on and cam and cam.is_position_behind(donde):
		on = false
	_btn.visible = on
	if on:
		_btn.icon = TouchIcons.get_icon({"empezar": "pve_empezar", "tienda": "pve_tienda", "jefe": "pve_jefe"}.get(id, "interact"))
		var c: Vector2 = cam.unproject_position(donde) if cam else get_viewport().get_visible_rect().size * 0.5
		# SIEMPRE A MANO: si el objeto queda en el borde (una caja en el suelo, a tus pies), el boton no se va
		# fuera ni se mete debajo de la barra de armas; se queda en la zona libre de la pantalla
		var vp := get_viewport().get_visible_rect().size
		c.x = clampf(c.x, _btn.size.x * 0.5 + 20.0, vp.x - _btn.size.x * 0.5 - 20.0)
		c.y = clampf(c.y, _btn.size.y * 0.5 + 90.0, vp.y - _btn.size.y * 0.5 - 150.0)
		_btn.position = c - _btn.size * 0.5


func _indice(id: String) -> int:
	for i in PUESTOS.size():
		if String(PUESTOS[i]["id"]) == id:
			return i
	return 0


## Empieza la oleada: se va el panel y, LA PRIMERA VEZ, suena la sirena de emergencia 15 s.
## `saltar_a` > 0 se salta lo que quede y va directo a esa oleada (la palanca del jefe).
func empezar_ya(saltar_a: int = 0) -> void:
	if not _esperando or terminado:
		return
	if saltar_a > 0 and saltar_a <= OLEADAS.size() and saltar_a > oleada:
		oleada = saltar_a - 1           # _empezar_oleada() suma uno
		if oro < ORO_SALTO_JEFE:
			oro = ORO_SALTO_JEFE        # ver ORO_SALTO_JEFE: llegar pelado al jefe no es pelear
		_mensaje("SALTANDO A LA OLEADA %d · ◈%d PARA EQUIPARTE" % [saltar_a, oro])
	_esperando = false
	_mostrar_puestos(false)
	if not _auto and not _alarma_sonada and _alarma and _alarma.stream:
		# LA SIRENA MANDA: suena 15 s y la oleada sale al apagarse. Es el aviso de que ya vienen.
		_alarma_sonada = true
		_alarma.volume_db = 0.0
		_alarma.play()
		_alarma_t = ALARMA_S
		var tw := create_tween()
		tw.tween_interval(ALARMA_S - ALARMA_FIN)
		tw.tween_property(_alarma, "volume_db", -40.0, ALARMA_FIN)
		tw.tween_callback(_alarma.stop)
		_mensaje("LLEGAN EN %d SEGUNDOS" % int(ALARMA_S))
		Net.net_alarma()               # que suene tambien en las otras pantallas
		return
	_empezar_oleada()


## COMPRAR, CON EL ORO EN COMUN. El bote lo lleva el anfitrion: lo que gana uno matando lo gasta
## cualquiera. Si compra un invitado, pide permiso; el anfitrion cobra y le contesta, y entonces el
## articulo se le aplica EN SU MAQUINA (su munición, su armadura, sus botiquines).
func _comprar(id: String) -> void:
	if _en_red and not _soy_host:
		Net.net_comprar(id)             # el anfitrion cobra y contesta (_aplicar_compra)
		return
	if not cobrar_a_distancia(id):
		return
	efecto_de_mundo(id)
	_aplicar_compra(id)


## Cobra el articulo del bote comun si alcanza. Lo usa tanto el anfitrion para el mismo como para
## atender la peticion de un invitado.
func cobrar_a_distancia(id: String) -> bool:
	for x in TIENDA:
		if String(x["id"]) == id:
			if oro < int(x["precio"]):
				return false
			oro -= int(x["precio"])
			return true
	return false


## El efecto del articulo, aqui y ahora: esto corre en la maquina de quien compra.
func _aplicar_compra(id: String) -> void:
	if not is_instance_valid(jugador):
		return
	match id:
		"municion":
			if not ("ammo" in jugador and "reserve" in jugador):
				return
			# SE ACUMULA, NO SE REPONE. Antes esto era `maxi(reserve, reserve_de_fabrica)`: con la
			# reserva ya llena, comprar municion no hacia NADA y te quedabas sin el oro. En el modo
			# oleadas el oro es para gastarlo, y aguantar la oleada 9 con la reserva de fabrica no da:
			# si compras cuatro veces, llevas cuatro cargas.
			for i in jugador.ammo.size():
				var w: Dictionary = Weapons.LIST[i] if i < Weapons.LIST.size() else {}
				jugador.set_ammo(i, int(w.get("mag", jugador.ammo[i])))
				jugador.set_reserve(i, int(jugador.reserve[i]) + int(w.get("reserve", 120)))
			if "current" in jugador and jugador.has_signal("ammo_changed"):
				var cw: Dictionary = Weapons.LIST[jugador.current] if jugador.current < Weapons.LIST.size() else {}
				jugador.ammo_changed.emit(int(jugador.ammo[jugador.current]), int(jugador.reserve[jugador.current]), String(cw.get("name", "")))
			_mensaje("MUNICION REPUESTA")
		"botiquin":
			# NO CURA EN EL SITIO: deja cuatro cajas en el suelo delante de la maquina, y las coges
			# cuando te hagan falta (tambien a mitad de la oleada, si consigues volver).
			# EN RED LAS PONE EL ANFITRION (`efecto_de_mundo`), para todos. Aqui solo sin red: si las
			# soltara tambien el que compra, en su pantalla habria ocho.
			if not _en_red:
				_soltar_botiquines(4)
			_mensaje("CUATRO BOTIQUINES EN EL SUELO")
		"armadura":
			if not jugador.has_method("poner_armadura"):
				return
			# TAMBIEN SE ACUMULA. Con el tope de 100 comprar la segunda placa era tirar el oro.
			if "armadura_tope" in jugador:
				jugador.armadura_tope = float(jugador.armadura_tope) + 100.0
			var antes: float = float(jugador.armor) if "armor" in jugador else 0.0
			jugador.poner_armadura(antes + 100.0)
			_mensaje("ARMADURA %d" % int(jugador.armor if "armor" in jugador else 100))
		"laser":
			if Weapons.con_laser:
				return                      # ya lo llevas: no se cobra dos veces
			Weapons.con_laser = true
			Weapons.rebuild()
			if jugador.has_method("refresh_ammo_slots"):
				jugador.refresh_ammo_slots()
			_mensaje("FUSIL LASER EN LA ULTIMA RANURA")


## LO QUE UNA COMPRA DEJA EN EL MUNDO. Lo llama SOLO quien cobra -el anfitrion, o la partida sin red-,
## tanto si compra el como si atiende a un invitado. Lo personal (municion, armadura, laser) va aparte,
## en `_aplicar_compra`, en la maquina del que compra.
func efecto_de_mundo(id: String) -> void:
	if id == "botiquin" and _en_red:
		_botiquines_para_todos(4)


var _prox_botiquin := 1
var _botiquines: Dictionary = {}      ## red_id -> caja, para quitarla cuando otro la recoge


## ANFITRION: decide donde, les pone numero, los crea aqui y se lo dice a todos.
func _botiquines_para_todos(n: int) -> void:
	var ids: Array = []
	var pos: Array = []
	for p in _sitios_botiquines(n):
		ids.append(_prox_botiquin)
		pos.append(p)
		_crear_botiquin(_prox_botiquin, p)
		_prox_botiquin += 1
	Net.net_botiquines(ids, pos)


## INVITADO: el anfitrion ha soltado botiquines; se crean aqui en el mismo sitio y con el mismo numero.
func _red_botiquines(ids: Array, posiciones: Array) -> void:
	for i in mini(ids.size(), posiciones.size()):
		_crear_botiquin(int(ids[i]), posiciones[i])
		_prox_botiquin = maxi(_prox_botiquin, int(ids[i]) + 1)   # por si me toca heredar la partida


## Alguien lo ha recogido en su pantalla: fuera tambien de la mia.
func _red_botiquin_recogido(id: int) -> void:
	var b = _botiquines.get(id)
	_botiquines.erase(id)
	if is_instance_valid(b):
		b.queue_free()


func _crear_botiquin(id: int, p: Vector3) -> void:
	if _botiquines.has(id) and is_instance_valid(_botiquines[id]):
		return
	var b: Node3D = BotiquinSuelto.new()
	b.jugador = jugador
	b.red_id = id
	var padre: Node = contenedor if is_instance_valid(contenedor) else self
	padre.add_child(b)
	b.global_position = p
	_botiquines[id] = b


## Los deja en abanico delante de la maquina de la tienda, cada uno apoyado en su suelo.
func _soltar_botiquines(n: int) -> void:
	for p in _sitios_botiquines(n):
		var b: Node3D = BotiquinSuelto.new()
		b.jugador = jugador
		var padre: Node = contenedor if is_instance_valid(contenedor) else self
		padre.add_child(b)
		b.global_position = p


## DONDE van: en abanico delante de la maquina de la tienda, cada uno apoyado en su suelo.
func _sitios_botiquines(n: int) -> Array:
	var sitios: Array = []
	var maquina: Node3D = null
	for p in _puestos:
		if String(p["id"]) == "tienda" and is_instance_valid(p["nodo"]):
			maquina = p["nodo"]
	var centro: Vector3 = maquina.global_position if maquina else jugador.global_position
	var frente: Vector3 = -maquina.global_transform.basis.z if maquina else Vector3.FORWARD
	frente.y = 0.0
	frente = frente.normalized() if frente.length() > 0.05 else Vector3.FORWARD
	var lado: Vector3 = frente.cross(Vector3.UP).normalized()
	for i in n:
		var p: Vector3 = centro + frente * 1.5 + lado * ((float(i) - (n - 1) * 0.5) * 0.55)
		if world:
			var h: Dictionary = world.raycast(p + Vector3.UP * 3.0, Vector3.DOWN, 9.0)
			if h.get("hit", false):
				p.y = (h["position"] as Vector3).y
		sitios.append(p)
	return sitios


var _prueba_t := -1.0
var _prueba_mato := false
var _diag := false
var _prueba_diag_t := 5.0

# ---------------------------------------------------------------------------
# EL REFUGIO SE CAE (2026-09-23, idea 10). Desde la oleada 6, quien pase 25 s seguidos bajo techo oye
# crujir el edificio (aviso + temblor) y 3 s despues revientan cuatro apoyos a su alrededor: el analizador
# estructural hace el resto. No mata de golpe (las explosiones salen a 5-9 m); obliga a moverse en vez de
# atrincherarse siempre en el mismo cuarto. Lo decide el anfitrion y las explosiones van por red.
# ---------------------------------------------------------------------------
const REFUGIO_OLEADA := 6
const REFUGIO_S := 25.0
var _techo_t := {}          # id de jugador (0 = el local) -> segundos seguidos bajo techo
var _refugio_mira_t := 0.0
var _refugio_cd := 0.0

func _refugio_tick(dt: float) -> void:
	if not _soy_host or oleada < REFUGIO_OLEADA or world == null:
		return
	_refugio_cd = maxf(0.0, _refugio_cd - dt)
	_refugio_mira_t -= dt
	if _refugio_mira_t > 0.0:
		return
	_refugio_mira_t = 1.0
	var gente := {}
	if is_instance_valid(jugador) and float(jugador.get("health")) > 0.0:
		gente[0] = jugador
	if Net.is_online():
		for id in Net.remotes.keys():
			var r = Net.remotes[id]
			if is_instance_valid(r) and not bool(r.get("dead")):
				gente[int(id)] = r
	for id in gente.keys():
		var p: Vector3 = (gente[id] as Node3D).global_position
		var techo: bool = world.raycast(p + Vector3(0, 2.0, 0), Vector3.UP, 10.0).get("hit", false)
		_techo_t[id] = float(_techo_t.get(id, 0.0)) + 1.0 if techo else 0.0
		if _techo_t[id] >= REFUGIO_S and _refugio_cd <= 0.0:
			_techo_t[id] = 0.0
			_refugio_cd = 30.0
			_derrumbar_refugio(p)
			return

func _derrumbar_refugio(p: Vector3) -> void:
	var txt := "¡EL EDIFICIO CRUJE! ¡SAL DE AHI!"
	print("[pve] refugio: cruje el edificio en %s" % str(p.snapped(Vector3.ONE)))
	if hud and hud.has_method("flash_message"):
		hud.flash_message(txt)
	Net.net_aviso(txt)
	if is_instance_valid(jugador) and jugador.has_method("add_shake"):
		jugador.add_shake(0.25)
	await get_tree().create_timer(3.0).timeout
	if world == null:
		return
	var a0 := randf() * TAU
	for k in 4:
		var a: float = a0 + k * TAU / 4.0
		var dirh := Vector3(cos(a), 0.0, sin(a))
		var ojo := p + Vector3(0, 0.6, 0)
		var h: Dictionary = world.raycast(ojo, dirh, 9.0)
		if not h.get("hit", false) or ojo.distance_to(h.position) < 4.0:
			continue          # sin pared a esa distancia: ese lado no tiene apoyo que romper (o esta demasiado cerca)
		Net.net_explode(world, h.position, 1.4, 255)
	if is_instance_valid(jugador) and jugador.has_method("add_shake"):
		jugador.add_shake(0.5)

func _process(dt: float) -> void:
	var _pf0 := Time.get_ticks_usec()
	_process_sin_medir(dt)
	Prof.add("pve", Time.get_ticks_usec() - _pf0)


func _process_sin_medir(dt: float) -> void:
	# El estado ordinario confirma que la ultima oleada quedo en cero. Si el
	# aviso de final se pierde, se le pide al anfitrion hasta recibirlo.
	if _en_red and not _soy_host and not terminado and oleada >= OLEADAS.size() and _quedan_red == 0:
		_fin_vigia += dt
		_fin_pide -= dt
		if _fin_vigia >= 3.0 and _fin_pide <= 0.0:
			_fin_pide = 2.0
			Net.pedir_fin_pve()
	else:
		_fin_vigia = 0.0
		_fin_pide = 0.0
	_aliados_tick(dt)
	_refugio_tick(dt)
	if _diag and is_instance_valid(jugador):
		_prueba_diag_t -= dt
		if _prueba_diag_t <= 0.0:
			_prueba_diag_t = 5.0
			for c in _vivos:
				if not is_instance_valid(c) or c.muerta:
					continue
				var ojo: Vector3 = c.global_position + Vector3.UP * float(c.datos.get("alto", 1.8)) * 0.8
				var vista: bool = world.has_line_of_sight(ojo, jugador.global_position + Vector3.UP * 1.2)
				# el camino: cuantos puntos trae y A QUE DISTANCIA DE TI ACABA. Si acaba lejos, el A* no
				# llego y la criatura esta caminando hacia el punto mas cercano que encontro, no hacia ti.
				var fin: Vector3 = c._path[c._path.size() - 1] if not c._path.is_empty() else c.global_position
				print("[pvediag] %s dist %.1f vista %s suelo %s vel %.1f clip %s x%.2f ataque_t %.1f golpe_t %.1f camino %d acaba_a %.1f atasco %.1f" % [c.tipo,
					Vector2(c.global_position.x - jugador.global_position.x, c.global_position.z - jugador.global_position.z).length(),
					str(vista), str(c.on_floor), Vector2(c.velocity.x, c.velocity.z).length(), c._anim_actual,
					c._anim.speed_scale if c._anim else 0.0, c._ataque_t, c._golpe_t, c._path.size(),
					Vector2(fin.x - jugador.global_position.x, fin.z - jugador.global_position.z).length(), c._atascado_t])
	if _prueba_t > 0.0:
		_prueba_t -= dt
		if is_instance_valid(jugador) and "health" in jugador:
			jugador.health = 100.0          # en la prueba el jugador no muere: se quiere ver a los bichos
		if _prueba_t < 10.0 and not _prueba_mato:
			_prueba_mato = true             # a 10 s del final se matan los gordos: tienen que reventar
			var normales := 0
			for c in _vivos:
				if not (c.datos.get("explosion", {}) as Dictionary).is_empty():
					c.take_damage(1.0e6)
				elif normales < 2:
					normales += 1           # y un par de corrientes, para ver caer el cadaver con sus huesos
					c.take_damage(1.0e6)
		if _prueba_t <= 0.0:
			var tipos := {}
			for c in _vivos:
				tipos[c.tipo] = int(tipos.get(c.tipo, 0)) + 1
			var linea := "[pveoleada] oleada=%d vivos=%s bajas=%d eventos=%s" % [oleada, str(tipos), bajas, str(CriaturaScript.eventos)]
			print(linea)
			# EN ESTA MAQUINA LA CONSOLA NO LLEGA (headless se traga los print), asi que el resultado de la
			# prueba tambien va a un fichero, que es lo unico que se puede leer despues.
			var _f2 := FileAccess.open("user://sonda_pve.txt", FileAccess.WRITE)
			if _f2:
				_f2.store_line(linea)
				_f2.close()
			get_tree().quit()
			return
	if _en_red and not _soy_host:
		# el invitado no lleva oleadas, pero SI usa los puestos: mira, pulsa y compra como el que mas
		if _puestos_fuera and not _puestos.is_empty():
			_usar_puestos()
			_marcar_boton(true)
		return
	# CON LA PARTIDA PERDIDA LAS CRIATURAS SIGUEN VIAJANDO. Aqui se salia antes de mandar las posturas, y en el
	# anfitrion los bichos siguen moviendose sobre los cadaveres mientras en el invitado se quedaban clavados
	# donde estaban al caer el ultimo jugador: medido con --diagsync, 24 m entre las dos copias de la misma
	# criatura en la pantalla de derrota.
	if terminado and _en_red and world != null:
		_vivos = _vivos.filter(func(c): return is_instance_valid(c) and not c.muerta)
		_red_t -= dt
		if _red_t <= 0.0:
			_red_t = 0.1
			_mandar_estados()
		return
	if terminado or world == null or not is_instance_valid(jugador):
		return
	_vivos = _vivos.filter(func(c): return is_instance_valid(c) and not c.muerta)
	if _en_red:
		_red_t -= dt
		if _red_t <= 0.0:
			_red_t = 0.1                # diez veces por segundo: suficiente para que no de tirones
			_mandar_estados()
		_estado_t -= dt
		if _estado_t <= 0.0:
			_estado_t = 0.5             # oleada, oro y puestos: con dos veces por segundo sobra
			Net.net_estado_pve(oleada, _cola.size() + _vivos.size(), oro, _puestos_fuera, "", bajas)
			_repite_sitio += 1
			if _repite_sitio % 4 == 0:
				_mandar_puestos()       # cada dos segundos: quien entre tarde tambien los ve
	# LA PRIMERA OLEADA ENTRA CON LA SIRENA: le das a empezar, suena la alarma de emergencia y los bichos
	# salen justo cuando se apaga. Mientras, la cuenta atras a la vista.
	if _alarma_t > 0.0:
		_alarma_t -= dt
		var cuenta := "OLEADA %d EN %d s" % [oleada + 1, ceili(maxf(_alarma_t, 0.0))]
		_objetivo(cuenta)
		# LA CUENTA ATRAS TAMBIEN VIAJA. Aqui se salia de la funcion antes de mandar nada, asi que los
		# demas se quedaban con el cartel viejo los quince segundos de sirena.
		if _en_red:
			_estado_t -= dt
			if _estado_t <= 0.0:
				_estado_t = 0.5
				Net.net_estado_pve(oleada, 0, oro, false, cuenta, bajas)
		if _alarma_t <= 0.0:
			_empezar_oleada()
		return
	if _esperando:
		# las pruebas no tienen quien pulse el boton: alli si arranca sola
		if _auto:
			_descanso_t -= dt
			if _descanso_t <= 0.0:
				empezar_ya()
		else:
			_usar_puestos()
			_marcar_boton(true)     # cada cuadro: la marca va pegada al boton, gires donde gires
			_objetivo("OLEADA %d · usa el puesto rojo para empezar · ◈ %d" % [oleada + 1, oro])
		return
	_rescatar_atascados(dt)
	_salir_t -= dt
	if not _cola.is_empty() and _salir_t <= 0.0 and _vivos.size() < MAX_VIVOS:
		_salir_t = SALIDA_CADA
		_sacar(String(_cola.pop_front()))
	var jefe_txt := ""
	for c in _vivos:
		if bool(c.datos.get("jefe", false)):
			jefe_txt = " · %s %d%%" % [String(c.datos.get("nombre", "JEFE")), ceili(maxf(c.vida, 0.0) / float(c.datos.get("vida", 1.0)) * 100.0)]
	var cartel := "OLEADA %d/%d%s · quedan %d · %d puntos" % [oleada, OLEADAS.size(), jefe_txt, _cola.size() + _vivos.size(), puntos]
	_objetivo(cartel)
	if _cola.is_empty() and _vivos.is_empty():
		if oleada >= OLEADAS.size():
			terminado = true
			_mensaje("VICTORIA · has aguantado las %d oleadas" % oleada)
			_objetivo("VICTORIA · %d bajas · %d puntos" % [bajas, puntos])
			# ANTES que la pantalla propia: `_fin` puede cambiar de escena, y despues ya no hay a quien
			# mandar nada
			if _en_red:
				Net.net_fin_pve(true, oleada, bajas, puntos)
			_fin(true)
		else:
			_mensaje("OLEADA %d SUPERADA" % oleada)
			# EL QUE SE QUEDO MIRANDO VUELVE. Superar la oleada rescata a los caidos: es lo que hace
			# que valga la pena seguir peleando cuando tu compañero ya no esta.
			# POR RED: antes esto solo revivia al jugador de ESTA maquina, y el PvE solo corre en el
			# anfitrion. El invitado muerto se quedaba de espectador para siempre aunque su compañero
			# hubiera superado la oleada -lo vio el usuario: salio la tienda y los muertos seguian
			# mirando-.
			Net.net_revivir_caidos()
			_descanso_t = DESCANSO
			_esperando = true
			_mostrar_puestos(true)


func _empezar_oleada() -> void:
	get_tree().call_group("aliados_pve", "recargar_reserva")       # los compañeros bot, con la reserva llena
	# --sinoleadas: el modo sin bichos, para probar cosas del jugador (la linterna, el mapa) con calma
	if "--sinoleadas" in OS.get_cmdline_user_args():
		return
	oleada += 1
	_cola.clear()
	var jefe := false
	for grupo in OLEADAS[oleada - 1]:
		for i in int(grupo[1]):
			_cola.append(String(grupo[0]))
	_cola.shuffle()
	# PRUEBA --pvesolo=<tipo>: la oleada es solo tres de ese tipo (para ver un comportamiento concreto)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pvesolo=") and TIPOS.has(a.substr(10)):
			_cola = [a.substr(10), a.substr(10), a.substr(10)]
	# el jefe sale el primero: es lo que tiene que verse al empezar la ultima oleada
	for t in _cola:
		if bool(TIPOS[t].get("jefe", false)):
			_cola.erase(t)
			_cola.push_front(t)
			jefe = true
			break
	_salir_t = 0.0
	_mensaje(("OLEADA %d · ¡EL GOLIAT!" % oleada) if jefe else ("OLEADA %d" % oleada))
	print("[pve] oleada %d: %d criaturas" % [oleada, _cola.size()])


func _sacar(t: String, donde = null) -> void:
	var datos: Dictionary = TIPOS[t]
	var pos = donde if donde != null else _punto_salida()
	if pos == null:
		_cola.push_back(t)             # no hay sitio ahora: vuelve a la cola
		return
	var c: CharacterBody3D = CriaturaScript.new()
	contenedor.add_child(c)
	c.global_position = pos
	c.setup(t, datos, world, jugador)
	# UNO DE CADA TRES SALE OBSESIVO: elige presa al aparecer y no la suelta. Los otros dos van
	# siempre a por el que tengan mas cerca. La mezcla es lo que hace que una oleada no se lea toda
	# igual: los oportunistas se reparten y los obsesivos te persiguen aunque te escondas detras de
	# un companero.
	c._obsesiva = randf() < 0.34
	c.murio.connect(_on_murio)
	c.invoca.connect(_on_invoca)
	c.red_id = _prox_id
	_prox_id += 1
	Net.net_criatura_nueva(c.red_id, t, pos)
	_vivos.append(c)


## BICHOS ATASCADOS. Aunque se compruebe el camino al salir, alguno se queda enganchado detras de un
## muro o encima de algo (y con el mapa rompiendose, los caminos cambian). Si en 10 s no se ha acercado
## ni un metro y sigue lejos, reaparece en otro punto con camino. Cerca no se toca: ahi esta peleando.
const ATASCO_S := 10.0
const ATASCO_REVISA := 2.0
var _atasco_revisa_t := ATASCO_REVISA

func _rescatar_atascados(dt: float) -> void:
	_atasco_revisa_t -= dt
	if _atasco_revisa_t > 0.0:
		return
	_atasco_revisa_t = ATASCO_REVISA
	for c in _vivos:
		if bool(c.get("dormida")) or (bool(c.datos.get("bruja", false)) and int(c._bruja_estado) < 3):
			continue                   # la campaña: esta quieta a proposito (criatura.gd, DORMIDA)
		var d: float = c.global_position.distance_to(jugador.global_position)
		var antes: float = float(c.get_meta("pve_dist", INF))
		if d < antes - 1.0 or d < 10.0:
			c.set_meta("pve_dist", d)
			c.set_meta("pve_quieto", 0.0)
			continue
		var quieto: float = float(c.get_meta("pve_quieto", 0.0)) + ATASCO_REVISA
		c.set_meta("pve_quieto", quieto)
		if quieto >= ATASCO_S:
			if _diag:
				var ojo: Vector3 = c.global_position + Vector3.UP * float(c.datos.get("alto", 1.8)) * 0.8
				print("[pvediag] ABRE PASO %s a %.1f m · la estabas viendo: %s" % [c.tipo, d,
					str(world.has_line_of_sight(ojo, jugador.global_position + Vector3.UP * 1.2))])
			# QUE SE ABRA PASO, NO QUE APAREZCA EN OTRO LADO. Antes aqui se la reubicaba en un punto de
			# salida con camino, y eso desde fuera se ve como que el bicho desaparece y se teletransporta.
			if c.has_method("abrir_paso"):
				c.abrir_paso()
			c.set_meta("pve_dist", d)
			c.set_meta("pve_quieto", 0.0)


## Un aullador ha llamado refuerzos: salen a su lado (si hay suelo), sin pasar por la cola.
func _on_invoca(t: String, pos: Vector3) -> void:
	if terminado or _vivos.size() >= MAX_VIVOS + 4 or not TIPOS.has(t):
		return
	var h: Dictionary = world.raycast(pos + Vector3.UP * 2.5, Vector3.DOWN, 6.0)
	if h.get("hit", false):
		_sacar(t, (h["position"] as Vector3) + Vector3(0, 0.2, 0))


## Un sitio de suelo cerca del jugador donde quepa de pie. Rayos contra los voxels: del aire hacia
## abajo hasta dar con suelo a una altura parecida a la del jugador, y hueco encima. Si lejos no hay
## (fuera del mapa, dentro de un muro) se prueba mas cerca.
# ---------------------------------------------------------------------------
# EL RUIDO ATRAE (2026-09-23, idea 8). Una explosion o un mazazo enfurece a las criaturas que haya cerca
# (40 % mas rapidas, 3 s: criatura.enfurecer) y durante 8 s las que salgan lo hacen cerca de ese ruido, no
# alrededor del jugador. Reventar paredes deja de ser gratis: te abre camino y te trae compañia.
# ---------------------------------------------------------------------------
var _ruido_pos := Vector3.ZERO
var _ruido_t := -100.0
const RUIDO_ATRAE_S := 8.0
var _enfurecidas := 0

func ruido(pos: Vector3, radio: float) -> void:
	if not _soy_host:
		return
	_ruido_pos = pos
	_ruido_t = Time.get_ticks_msec() * 0.001
	var alcance: float = 14.0 + radio * 8.0
	for c in get_tree().get_nodes_in_group("criaturas"):
		if is_instance_valid(c) and c.has_method("enfurecer") and (c as Node3D).global_position.distance_to(pos) < alcance:
			c.enfurecer(3.0)
			_enfurecidas += 1
	if "--pveruido" in OS.get_cmdline_user_args():
		print("[pve] ruido en %s: %d enfurecidas en total" % [str(pos.snapped(Vector3.ONE)), _enfurecidas])

var _sector := 0
var _ultimas_salidas: Array = []

func _punto_salida() -> Variant:
	var base: Vector3 = jugador.global_position
	# con ruido reciente, seis de cada diez salen por alli (el camino hasta el jugador se sigue comprobando)
	if Time.get_ticks_msec() * 0.001 - _ruido_t < RUIDO_ATRAE_S and randf() < 0.6:
		base = _ruido_pos
		if "--pveruido" in OS.get_cmdline_user_args():
			print("[pve] sale una junto al ruido (%s)" % str(base.snapped(Vector3.ONE)))
	var reserva = null                 # un suelo valido sin camino comprobado, por si no hay otro
	var caminos := 0
	# REPARTIDOS (2026-09-23, pedido: "que no aparezcan todos en el mismo spawn"). Se quedaba con el PRIMER
	# sitio con camino, y si solo habia una zona accesible salian siempre de ahi. Ahora el giro va por sectores
	# (cada salida empieza en otro octavo del circulo) y en los primeros 30 intentos se descarta lo que caiga a
	# menos de 10 m de las ultimas seis salidas.
	_sector = (_sector + 3) % 8
	for intento in 40:
		var a := (float(_sector) + randf()) * TAU / 8.0 + float(intento) * 0.9
		var r := randf_range(RADIO_SALIDA.x, RADIO_SALIDA.y) * (1.0 if intento < 20 else 0.55)
		var arriba := Vector3(base.x + cos(a) * r, base.y + 6.0, base.z + sin(a) * r)
		var h: Dictionary = world.raycast(arriba, Vector3.DOWN, 20.0)
		if not h.hit or (h.normal as Vector3).y < 0.7:
			continue
		var suelo: Vector3 = h.position
		if intento < 30 and _ultimas_salidas.any(func(q: Vector3): return q.distance_to(suelo) < 10.0):
			continue
		if arriba.y - suelo.y < 0.2 or absf(suelo.y - base.y) > 6.0:
			continue                   # el rayo nacio dentro de un muro, o es otro piso
		if world.raycast(suelo + Vector3.UP * 0.1, Vector3.UP, 2.0).hit:
			continue                   # no cabe de pie
		if reserva == null:
			reserva = suelo + Vector3(0, 0.2, 0)
		# QUE HAYA CAMINO HASTA EL JUGADOR: un bicho que sale detras de un muro sin salida se queda ahi
		# toda la oleada. El A* devuelve lo mas cerca que llego; si acaba lejos del jugador, no vale.
		if caminos >= 8:
			break                      # cada A* cuesta: ocho intentos como mucho
		caminos += 1
		var camino: PackedVector3Array = world.find_path(suelo + Vector3(0, 0.2, 0), base)
		if camino.is_empty():
			continue
		var fin: Vector3 = camino[camino.size() - 1]
		if Vector2(fin.x - base.x, fin.z - base.z).length() < 3.0 and absf(fin.y - base.y) < 2.0:
			_ultimas_salidas.append(suelo)
			if _ultimas_salidas.size() > 6:
				_ultimas_salidas.pop_front()
			return suelo + Vector3(0, 0.2, 0)
	# PISTAS DEL MAPA: si alrededor no hubo sitio con camino, los puntos de salida que dejo el generador
	# (los mas cercanos entre 12 y 90 m, con suelo y camino hasta el jugador)
	var cerca := _pistas.filter(func(q: Vector3): return Vector2(q.x - base.x, q.z - base.z).length() > 12.0 \
		and Vector2(q.x - base.x, q.z - base.z).length() < 90.0)
	cerca.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(base) < b.distance_squared_to(base))
	for q in cerca.slice(0, 4):
		var hq: Dictionary = world.raycast(q + Vector3.UP * 3.0, Vector3.DOWN, 8.0)
		if not hq.get("hit", false):
			continue
		var sq: Vector3 = (hq["position"] as Vector3) + Vector3(0, 0.2, 0)
		var cq: PackedVector3Array = world.find_path(sq, base)
		if not cq.is_empty() and Vector2(cq[cq.size() - 1].x - base.x, cq[cq.size() - 1].z - base.z).length() < 3.0:
			return sq
	return reserva


## PISTAS DE SALIDA del mapa: res://maps/<mapa>.pve.json, lista "criaturas" (puntos de suelo en metros).
var _pistas: Array = []

func _mapa() -> String:
	var escena := get_parent()
	return String(escena.current_map) if escena and "current_map" in escena else String(Settings.map)


func _cargar_pistas() -> void:
	var ruta := "res://maps/%s.pve.json" % _mapa()
	if not FileAccess.file_exists(ruta):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if j is Dictionary:
		for p in j.get("criaturas", []):
			if p is Array and p.size() >= 3:
				_pistas.append(Vector3(float(p[0]), float(p[1]), float(p[2])))


func _on_murio(c: Node) -> void:
	Net.net_criatura_muerta(int(c.get("red_id")), c.get("_ultimo_empuje") if "_ultimo_empuje" in c else Vector3.ZERO)
	bajas += 1
	_poner_bajas()
	var p := int(TIPOS.get(String(c.tipo), {}).get("puntos", 100))
	puntos += p
	# ORO PARA LA TIENDA: lo que vale el bicho. Un zombi deja 10, el Goliat 500.
	oro += maxi(1, int(round(p * ORO_POR_PUNTO)))


# ---------------------------------------------------------------------------
# EL LADO DE LOS INVITADOS. Aqui no hay oleadas ni inteligencia: llegan avisos del anfitrion y se
# dibuja lo que dice. Una criatura remota no piensa, no busca camino y no tiene fisica (ver
# criatura.gd, `remota`): solo se desliza al sitio que le mandan.
# ---------------------------------------------------------------------------
## EL ANFITRION DICE DONDE ESTAN LOS PUESTOS (los puso delante de SU salida, que no es la mia).
func _red_puestos_sitio(sitios: Array, giro: float) -> void:
	if not _puestos.is_empty() or sitios.is_empty():
		return
	_alarma = AudioStreamPlayer.new()
	add_child(_alarma)
	add_to_group("puestos_pve")
	Minimapa.quitar_sitio("pve_boton")
	for i in PUESTOS.size():
		var d: Dictionary = PUESTOS[i]
		var p: Vector3 = sitios[mini(i, sitios.size() - 1)]
		var n := _hacer_puesto(d)
		add_child(n)
		n.global_position = p - Vector3(0.0, HUNDE, 0.0)
		n.rotation.y = giro
		_puestos.append({"id": String(d["id"]), "nodo": n, "y": p.y})
	_mostrar_puestos(_puestos_fuera)


## La sirena, en la maquina del invitado: el mismo sonido, los mismos 15 s y el mismo desvanecido.
func _red_alarma() -> void:
	if _alarma == null or _alarma.stream == null:
		if _alarma and ResourceLoader.exists(ALARMA):
			_alarma.stream = load(ALARMA)
		if _alarma == null or _alarma.stream == null:
			return
	_alarma.volume_db = 0.0
	_alarma.play()
	var tw := create_tween()
	tw.tween_interval(ALARMA_S - ALARMA_FIN)
	tw.tween_property(_alarma, "volume_db", -40.0, ALARMA_FIN)
	tw.tween_callback(_alarma.stop)
	_mensaje("LLEGAN EN %d SEGUNDOS" % int(ALARMA_S))


## Y como va todo: oleada, cuantos quedan, el oro (comun) y si los puestos estan fuera.
func _red_estado_pve(n_oleada: int, quedan: int, p_oro: int, fuera: bool, texto: String, p_bajas: int = 0) -> void:
	_quedan_red = quedan
	oleada = n_oleada
	oro = p_oro
	if p_bajas != bajas:
		bajas = p_bajas
		_poner_bajas()
	if texto != "":
		_objetivo(texto)
	elif quedan > 0:
		_objetivo(_cartel_invitado(n_oleada, quedan))
	if fuera != _puestos_fuera and not _puestos.is_empty():
		_mostrar_puestos(fuera)
	_puestos_fuera = fuera
	_esperando = fuera
	if is_instance_valid(_ventana):
		_ventana.poner_oro(oro)


## El anfitrion manda a los invitados donde ha puesto los puestos.
func _mandar_puestos() -> void:
	if not _en_red or _puestos.is_empty():
		return
	# en el orden de PUESTOS, que es el que usa el invitado para saber cual es cual
	var sitios: Array = []
	var giro := 0.0
	for d in PUESTOS:
		for p in _puestos:
			if String(p["id"]) != String(d["id"]):
				continue
			var n: Node3D = p["nodo"]
			giro = n.rotation.y
			sitios.append(Vector3(n.global_position.x, float(p["y"]), n.global_position.z))
			break
	Net.net_puestos_sitio(sitios, giro)


func _red_nueva(id: int, tipo: String, pos: Vector3) -> void:
	if not TIPOS.has(tipo) or _remotas.has(id):
		return
	var c: CharacterBody3D = CriaturaScript.new()
	c.remota = true
	c.soy_copia = true              # ni rompe ni hace daño: eso lo reparte el anfitrion
	c.red_id = id
	contenedor.add_child(c)
	c.global_position = pos
	c.setup(tipo, TIPOS[tipo], world, jugador)
	c.set_physics_process(true)
	_remotas[id] = c


## EL INVITADO SE CURA SOLO SI LE FALTA UN BICHO.
##
## El aviso de nacimiento se manda UNA VEZ. El censo al entrar tapa el caso de llegar tarde, pero no
## tapa nada de lo que pueda pasar despues: un aviso que llega mientras todavia no hay nadie
## escuchando, una migracion de anfitrion, un bicho invocado por otro en mal momento... y el
## resultado siempre es el mismo y es el peor de todos: UN BICHO QUE TE PEGA Y NO ESTA. El usuario lo
## vio dos veces ("veo zombies transparentes que me atacan, no los veo").
##
## No hace falta adivinar la causa. El anfitrion manda diez veces por segundo la lista de TODOS los
## que estan vivos: si aparece un numero que yo no tengo, es que me perdi su nacimiento, y con pedir
## el censo otra vez se arregla, venga de donde venga el agujero. Con enfriamiento, que si falta uno
## falta en los diez paquetes del segundo y no se va a pedir diez veces.
const RECENSO_CADA_S := 2.0
var _recenso_t := -RECENSO_CADA_S


## EL RELEVO: SE ME HA IDO EL ANFITRION Y AHORA MANDO YO.
##
## No hay que inventar nada, porque todo lo que hace falta YA esta en esta maquina: las criaturas son
## las mismas (copias con el mismo numero que las del anfitrion caido), y la oleada, el oro y si los
## puestos estan fuera me los ha ido mandando el anfitrion dos veces por segundo. Lo que falta es
## PENSAR: las copias pasan a ser criaturas de verdad, con su inteligencia, y esta maquina se pone a
## llevar las oleadas y a contestar el censo.
##
## Lo que SI se pierde son los bichos que el anfitrion tenia en cola y aun no habia sacado. La oleada
## sigue con los que hay en pie y se da por superada cuando caen, que es mejor que quedarse colgada.
func _al_migrar(soy_yo: bool) -> void:
	if not _en_red or terminado:
		return
	if not soy_yo:
		# Otro toma el mando: me quedo con mis copias -llevan los mismos numeros- y, en cuanto me
		# enganche a el, el recenso automatico pide las que falten.
		return
	if _soy_host:
		return
	_soy_host = true
	# lo que escuchaba como invitado ya no me toca: ahora esos avisos los mando yo
	for par in [[Net.criatura_nueva, _red_nueva], [Net.criatura_estado, _red_estado],
			[Net.roca_arrancada, _red_roca], [Net.criatura_muerta, _red_muerta],
			[Net.oleada_estado, _red_oleada], [Net.puestos_sitio, _red_puestos_sitio],
			[Net.estado_pve, _red_estado_pve], [Net.alarma_oleada, _red_alarma],
			[Net.compra_concedida, _aplicar_compra]]:
		if (par[0] as Signal).is_connected(par[1]):
			(par[0] as Signal).disconnect(par[1])
	# DE COPIA A CRIATURA DE VERDAD. Cada una conserva su numero, su sitio y su vida.
	var mayor := 0
	var vivas := 0
	for id in _remotas.keys():
		var c = _remotas[id]
		if not is_instance_valid(c) or bool(c.muerta):
			continue
		c.remota = false
		c.soy_copia = false
		if not c.murio.is_connected(_on_murio):
			c.murio.connect(_on_murio)
		if not c.invoca.is_connected(_on_invoca):
			c.invoca.connect(_on_invoca)
		_vivos.append(c)
		mayor = maxi(mayor, int(id))
		vivas += 1
	_remotas.clear()
	# los bichos nuevos no pueden repetir numero con los que ya hay
	_prox_id = maxi(_prox_id, mayor + 1)
	if not Net.piden_censo_criaturas.is_connected(_mandar_censo_criaturas):
		Net.piden_censo_criaturas.connect(_mandar_censo_criaturas)
	# si queda algun bicho en pie, la oleada sigue; si no, toca esperar a que alguien la empiece
	_esperando = _vivos.is_empty()
	if _esperando and not _puestos.is_empty():
		_mostrar_puestos(true)
	_mensaje("EL ANFITRIÓN SE FUE · AHORA LLEVAS TÚ LA PARTIDA")
	print("[pve] relevo: ahora llevo yo las oleadas · %d criaturas en pie · oleada %d · esperando=%s" % [
		vivas, oleada, str(_esperando)])


## `datos`: [id, x, y, z, giro, clip, ...] seguidos, tal y como los manda el anfitrion.
func _red_estado(datos: Array) -> void:
	_diag_recibidos += 1
	var i := 0
	var faltan := 0
	while i + 6 < datos.size():
		var id := int(datos[i])
		var c = _remotas.get(id)
		if is_instance_valid(c):
			c.poner_estado_red(Vector3(datos[i + 1], datos[i + 2], datos[i + 3]),
				float(datos[i + 4]), String(datos[i + 5]), float(datos[i + 6]))
		else:
			faltan += 1
		i += 7
	if faltan > 0:
		var ahora: float = float(Time.get_ticks_msec()) / 1000.0
		if ahora - _recenso_t >= RECENSO_CADA_S:
			_recenso_t = ahora
			print("[pve] me faltan %d bicho(s) que el anfitrion si tiene: pido el censo" % faltan)
			Net.pedir_censo_criaturas()


## El jefe ha arrancado un trozo de suelo en la maquina del anfitrion: aqui se hace el mismo socavon
## y se le pone la misma roca en la mano, para que la escena sea la misma en las dos pantallas.
func _red_roca(id: int, suelo: Vector3, radio: float, potencia: int, tam: float, color: Color) -> void:
	var mat := 0
	if world != null and world.has_method("get_material_at"):
		mat = int(world.get_material_at(suelo - Vector3.UP * 0.1))
	CriaturaScript.arrancar_del_suelo(world, suelo, radio, potencia, mat)
	var c = _remotas.get(id)
	if is_instance_valid(c) and c.has_method("poner_roca_red"):
		c.poner_roca_red(tam, color)


func _red_muerta(id: int, empuje: Vector3) -> void:
	var c = _remotas.get(id)
	_remotas.erase(id)
	if not is_instance_valid(c):
		return
	# se cae con fisica igual que en la maquina del anfitrion (no hace falta replicar el cadaver: el
	# resultado es parecido y no vale la pena gastar red en unos huesos que se van a disolver)
	c.remota = false
	c._muerte_de_red = true        # esta muerte la manda el anfitrion: se aplica aqui, no se reenvia
	c._ultimo_empuje = empuje
	c.take_damage(1.0e9, empuje)


func _red_oleada(n: int, quedan: int, texto: String) -> void:
	oleada = n
	if texto != "":
		_objetivo(texto)
	elif quedan > 0:
		# EL MISMO TEXTO que pone `_red_estado_pve`. Llegan los dos al invitado y, con formatos
		# distintos -uno con el oro y otro sin el-, el cartel saltaba de uno a otro.
		_objetivo(_cartel_invitado(n, quedan))


## EL CARTEL DEL INVITADO, el mismo desde `_red_oleada` y `_red_estado_pve` (con dos formatos saltaba de uno a
## otro). Lleva el jefe con su vida, como lo ve el anfitrion: la vida llega con la postura de cada bicho.
func _cartel_invitado(n: int, quedan: int) -> String:
	var jefe_txt := ""
	for c in _remotas.values():
		if is_instance_valid(c) and not bool(c.muerta) and bool(c.datos.get("jefe", false)):
			jefe_txt = " · %s %d%%" % [String(c.datos.get("nombre", "JEFE")), ceili(maxf(c.vida, 0.0) / float(c.datos.get("vida", 1.0)) * 100.0)]
	return "OLEADA %d%s · quedan %d · ◈ %d" % [n, jefe_txt, quedan, oro]


## El anfitrion manda diez veces por segundo donde esta cada bicho y que animacion lleva.
var _diag_mandados := 0            ## diagnostico: paquetes de postura enviados (anfitrion)
var _diag_recibidos := 0           ## y recibidos (invitado)


func _mandar_estados() -> void:
	var datos: Array = []
	for c in _vivos:
		if not is_instance_valid(c) or c.muerta or int(c.red_id) < 0:
			continue
		datos.append(int(c.red_id))
		datos.append(c.global_position.x)
		datos.append(c.global_position.y)
		datos.append(c.global_position.z)
		datos.append(c.rotation.y)
		datos.append(c._anim_actual)
		# LA VIDA TAMBIEN: sin ella la copia del invitado iba siempre llena (medido: 675 fotos distintas en
		# una oleada) y el cartel del jefe con su porcentaje solo lo veia el anfitrion
		datos.append(int(ceil(maxf(float(c.vida), 0.0))))
	Net.net_criaturas_estado(datos)
	_diag_mandados += 1


## EL CONTADOR DE BAJAS DEL HUD. Solo lo movia la muerte de un BOT (`main.gd::_on_enemy_died`); la de
## un bicho sumaba en `bajas` y no se lo decia a nadie, asi que en la cuarentena el contador se quedaba
## en 0 toda la partida, en todas las pantallas. Lo conto el usuario. Es el total del equipo, que es lo
## que lleva el modo oleadas.
func _poner_bajas() -> void:
	if hud and hud.has_method("set_kills"):
		hud.set_kills(bajas)


func _objetivo(t: String) -> void:
	if hud and hud.has_method("set_objective"):
		hud.set_objective(t, false)


func _mensaje(t: String) -> void:
	if _en_red and _soy_host:
		Net.net_aviso(t)               # "OLEADA SUPERADA", "VICTORIA"... tambien para los invitados
	if hud and hud.has_method("flash_message"):
		hud.flash_message(t)


# ---------------------------------------------------------------------------
# CAIDA, RESCATE Y FINAL
# ---------------------------------------------------------------------------

## ¿QUEDA ALGUIEN DE PIE APARTE DE MI? Solo cuentan personas: los bots no juegan al PvE, y en LAN los
## companeros son los `Net.remotes`. Sin nadie vivo, morir es el final de la partida.
func _companeros_vivos() -> int:
	# SE PREGUNTA A `Net.dead_players`, NO AL AVATAR REMOTO.
	#
	# Lo primero que escribi aqui miraba `r.health` del avatar remoto, y eso NO EXISTE: la vida la
	# lleva cada uno en su maquina ("el es la autoridad de su vida", net_player.gd), asi que el avatar
	# remoto no la tiene. Con el valor por defecto, cualquier compañero conectado contaba como vivo
	# aunque estuviera muerto, y entonces morir el ultimo no acababa la partida nunca.
	#
	# Lo que SI viaja es la muerte (`Net._death`, que corre en todas las maquinas y llena
	# `dead_players`). Esa es la lista buena.
	if not Net.is_online():
		return 0
	var n := 0
	var yo: int = multiplayer.get_unique_id()
	for id in Net.players.keys():
		var pid := int(id)
		if pid == yo:
			continue
		if not bool(Net.dead_players.get(pid, false)):
			n += 1
	return n


## Un jugador se ha quedado sin vida. Lo llama `player.die()`.
func jugador_caido() -> void:
	if terminado:
		return
	var vivos := _companeros_vivos()
	if vivos > 0:
		_mensaje("HAS CAIDO · %d compañero(s) en pie · vuelves si superan la oleada" % vivos)
		# ME QUEDO MIRANDO, PERO ATENTO: si cae el ultimo que sigue en pie, la partida se acaba
		# tambien para mi. Sin esto me quedaba espectando para siempre mientras el otro ya estaba
		# viendo su pantalla de derrota. Lo vio el usuario jugando a la cuarentena.
		if not Net.alguien_cayo.is_connected(_ha_caido_alguien):
			Net.alguien_cayo.connect(_ha_caido_alguien)
		return
	_perder()


## Alguien ha caido (en cualquier maquina). Si yo ya estaba mirando y no queda nadie en pie, se acabo.
func _ha_caido_alguien(_id: int) -> void:
	if terminado:
		return
	var yo_caido: bool = is_instance_valid(jugador) and "spectating" in jugador and bool(jugador.spectating)
	if not yo_caido:
		return
	if _companeros_vivos() > 0:
		return
	_perder()


func _perder() -> void:
	if terminado:
		return
	terminado = true
	_mensaje("DERROTA · has caido en la oleada %d" % maxi(oleada, 1))
	_objetivo("DERROTA · oleada %d · %d bajas · %d puntos" % [maxi(oleada, 1), bajas, puntos])
	# la derrota ya la detecta cada maquina al caer todos (`_ha_caido_alguien`), pero si a alguien se le
	# escapa el aviso de una muerte se quedaria mirando para siempre: el anfitrion la manda igual, y el
	# que ya la tenia la ignora
	if _en_red and _soy_host:
		Net.net_fin_pve(false, oleada, bajas, puntos)
	_fin(false)


## INVITADO: el anfitrion da la partida por acabada. Se abre la pantalla AQUI, con los numeros de la
## partida, y el premio lo cobra esta cuenta.
func _red_fin(gano: bool, n_oleada: int, n_bajas: int, n_puntos: int) -> void:
	if terminado:
		return
	terminado = true
	oleada = n_oleada
	bajas = n_bajas
	puntos = n_puntos
	_poner_bajas()
	if gano:
		_objetivo("VICTORIA · %d bajas · %d puntos" % [bajas, puntos])
	else:
		_objetivo("DERROTA · oleada %d · %d bajas · %d puntos" % [maxi(oleada, 1), bajas, puntos])
	_fin(gano)


## ANFITRION: todos los bichos que hay ahora mismo, al que acaba de decir que ya esta listo.
func _mandar_censo_criaturas(a_quien: int) -> void:
	var n := 0
	for c in _vivos:
		if not is_instance_valid(c):
			continue
		Net.net_criatura_nueva(int(c.red_id), String(c.tipo), c.global_position, a_quien)
		n += 1
	print("[pve] censo de criaturas para el jugador %d: %d bichos" % [a_quien, n])


## Devuelve a la pelea a los que se quedaron mirando.
## LOS COMPAÑEROS BOT MUERTOS: esperan al refugio / la oleada siguiente, o a que alguien les haga la RCP
var aliados_muertos: Dictionary = {}       ## hueco -> nombre

func aliado_muerto(h: int, nombre: String) -> void:
	aliados_muertos[h] = nombre
	_mensaje("UN COMPAÑERO HA CAÍDO · recógelo o hazle la RCP")


## RCP (rescate.gd): el bot vuelve donde le han levantado, con media vida
func revivir_aliado(h: int, pos: Vector3) -> void:
	if h < 0:
		h = int(aliados_muertos.keys()[0]) if not aliados_muertos.is_empty() else 0
	aliados_muertos.erase(h)
	var e = _nuevo_aliado(h)
	if e != null:
		e.global_position = pos + Vector3.UP * 0.3
		e.health = 50.0
		_mensaje("¡UN COMPAÑERO HA VUELTO!")


func _revivir_caidos() -> void:
	# los compañeros bot muertos vuelven tambien (junto a ti), y sus cuerpos se van. LOS CUERPOS SE QUITAN EN TODAS LAS
	# MAQUINAS (2026-10-15, bug LAN: "mi amigo revivio y se puso a hacer la RCP a alguien que no estaba, y aparecio un bot
	# quieto"): antes solo si `aliados_muertos` tenia algo, y esa lista solo la lleva el anfitrion; en el invitado los
	# cuerpos se quedaban y su RCP le pedia al anfitrion revivir un cuerpo que alli ya no existia
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and String(c.get_meta("rescate_team", "")) == "pve":
			var rd = c.get_meta("ragdoll", null)
			if rd != null and is_instance_valid(rd):
				rd.queue_free()
			c.queue_free()
	if not aliados_muertos.is_empty():
		aliados_muertos.clear()
		_aliados_t = 0.0
	if is_instance_valid(jugador) and jugador.has_method("revivir_en_oleada"):
		if "spectating" in jugador and bool(jugador.spectating):
			jugador.revivir_en_oleada()
			_mensaje("VUELVES A LA PELEA")


## FINAL DE LA PARTIDA, con su pantalla y su premio.
##
## Antes no habia ninguna: al aguantar las diez oleadas salia un cartel y ya. Ahora se pasa por la
## misma pantalla de resultado que los demas modos, y se cobra por ganar (perder no da nada).
func _fin(gano: bool) -> void:
	Estadisticas.fin_partida(gano)
	var mn = jugador.get_parent() if is_instance_valid(jugador) else null
	# el premio crece con lo lejos que hayas llegado, no solo con ganar
	var exp_ganada := 0
	var oro_ganado := 0
	if gano:
		exp_ganada = 600 + bajas * 4 + puntos / 10
		oro_ganado = 400 + bajas * 2
	var segs: int = int(mn.segundos_partida()) if mn != null and mn.has_method("segundos_partida") else 0
	# MIS bajas, no las del equipo. MVP: el que se ha llevado la mayor parte (60 % o mas de las del
	# equipo; jugando solo, todas). OBJETIVO: haberle quitado al jefe al menos un 10 % de la vida.
	var mias: int = Combat.partida_bajas_pve
	var vida_jefe: float = float((TIPOS.get("goliat", {}) as Dictionary).get("vida", 5000.0))
	var mvp: bool = mias > 0 and float(mias) >= float(bajas) * 0.6
	var premio: Dictionary = Settings.premiar(gano, exp_ganada, oro_ganado,
		{"modo": "pve", "segundos": segs, "oleada": oleada, "bajas": mias, "puntos": puntos,
		"dano": int(Combat.partida_dano), "objetivos": 1 if Combat.partida_dano_jefe >= vida_jefe * 0.1 else 0,
		"mvp": mvp})
	if mn != null and mn.has_method("fin_pve"):
		mn.fin_pve(gano, oleada, bajas, puntos, premio)


## --tocapve (con --touch): planta al jugador delante de la tienda y TOCA su boton con un toque de pantalla
## de verdad (InputEventScreenTouch, el proyecto no emula el raton desde el tacto). Mira si abre la ventana.
func _toca_test() -> void:
	await get_tree().create_timer(12.0).timeout
	for p in _puestos:
		if String(p["id"]) == "tienda" and is_instance_valid(p["nodo"]):
			var n: Node3D = p["nodo"]
			var f: Vector3 = n.global_transform.basis.z
			jugador.global_position = n.global_position + Vector3(f.x, 0, f.z).normalized() * 1.6
			jugador.look_at(n.global_position + Vector3.UP * 1.2, Vector3.UP)
	await get_tree().create_timer(1.0).timeout
	var vis := _btn != null and is_instance_valid(_btn) and _btn.visible
	print("[tocapve] boton visible: ", vis, " mirado: ", _mirado)
	if not vis:
		get_tree().quit()
		return
	var c: Vector2 = _btn.get_global_rect().get_center()
	for pr in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = c
		t.pressed = pr
		Input.parse_input_event(t)
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	print("[tocapve] tienda abierta tras el toque: ", is_instance_valid(_ventana))
	get_tree().quit()



# ======================================================================================================
# COMPAÑEROS BOT (aliado_pve.gd, 2026-09-25): los modos zombi son para cuatro. Si faltan personas, los pone
# el anfitrion (o tu, jugando solo) hasta completar; si entra alguien, se va uno. --sinaliados: sin ellos.
# ======================================================================================================
const AliadoScript := preload("res://scripts/aliado_pve.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const PLAZAS := 4
var _aliados_t := 2.0

func _aliados_tick(dt: float) -> void:
	_aliados_t -= dt
	if _aliados_t > 0.0:
		return
	_aliados_t = 0.3
	if "--sinaliados" in OS.get_cmdline_user_args() or contenedor == null or world == null or not is_instance_valid(jugador):
		return
	if Net.is_online() and not Net.hosting:
		return
	var personas: int = Net.player_count() if Net.is_online() else 1
	var bots: Array = get_tree().get_nodes_in_group("aliados_pve")
	# los que han muerto no se reponen hasta el refugio o la oleada siguiente (o hasta que alguien les haga la RCP)
	var faltan: int = maxi(0, PLAZAS - personas - aliados_muertos.size())
	if bots.size() < faltan:
		var usados: Array = bots.map(func(b): return int(b.hueco)) + aliados_muertos.keys()
		var h := 0
		while h in usados:
			h += 1
		_nuevo_aliado(h)
	elif bots.size() > faltan:
		bots[bots.size() - 1].queue_free()        # ha entrado alguien: le deja su sitio


func _nuevo_aliado(h: int):
	var e = EnemyScene.instantiate()
	e.set_script(AliadoScript)
	e.hueco = h
	e.campana = self
	e.team = "pve"
	contenedor.add_child(e)
	e.global_position = jugador.global_position + Vector3(1.5, 0.5, 1.5)
	e.setup(world, jugador, 900 + h)
	# un nombre de jugador (main.NOMBRES_BOTS), como los bots de las partidas
	var g = Net.game if "game" in Net else null
	var nom: String = g.nombre_bot(h) if g != null and is_instance_valid(g) and g.has_method("nombre_bot") else "BOT %d" % (h + 1)
	e.set_bot_name(nom)
	e.teletransportar_a(jugador)
	print("[aliados] entra %s" % nom)
	return e


## --aliadostest (con la campaña: --map=campana_huida --pve): aparecen los tres, matan a un zombi, curan al
## jugador herido y le siguen de un salto cuando se va lejos
func prueba_aliados() -> void:
	await get_tree().create_timer(5.0).timeout
	jugador.set("invulnerable", true)
	var bots: Array = get_tree().get_nodes_in_group("aliados_pve")
	print("[aliados] bots: %d" % bots.size())
	var ok := bots.size() == 3
	jugador.global_position = Vector3(70.0, 1.3, 41.0)          # la calle Olmo (campaña)
	await get_tree().create_timer(4.0).timeout
	var ds := bots.map(func(b): return snappedf(b.global_position.distance_to(jugador.global_position), 0.1))
	print("[aliados] tras saltar a la calle, a %s m del jugador" % str(ds))
	if ds.any(func(d): return d > 8.0):
		ok = false
	_sacar("zombi", jugador.global_position + Vector3(14.0, 0.2, 0.0))
	var z = _vivos.back()
	if z.has_method("despertar"):
		z.despertar(false)
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--fotobalas=") and jugador.get("effects") != null:
			# primero, unas balas conocidas: de al lado de la camara hacia el fondo, y la foto en pleno vuelo
			jugador.global_position = Vector3(58.0, 1.3, 41.0)
			jugador.set("look", Vector2(-PI / 2, 0.0))
			jugador.rotation.y = -PI / 2
			await get_tree().create_timer(0.5).timeout
			var cam := get_viewport().get_camera_3d()
			var fwd := -cam.global_transform.basis.z
			var der := cam.global_transform.basis.x
			for k in 5:
				var desde: Vector3 = cam.global_position + fwd * 1.0 + der * (0.6 + k * 0.5) - cam.global_transform.basis.y * 0.25
				jugador.effects.tracer(desde, desde + fwd * 40.0 + der * (k - 2) * 1.5)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var fx = jugador.effects
			print("[balas] calidad %d · balas en vuelo %d · en el arbol %s · primera %s" % [int(fx.quality), fx._tracers.size(), str(fx.is_inside_tree()),
				str((fx._tracers[0][0] as Node3D).global_position) if fx._tracers.size() > 0 else "-"])
			get_viewport().get_texture().get_image().save_png(String(f).substr(12) % 9)
		if String(f).begins_with("--fotobalas="):
			# foto de las balas viajando: mirando al zombi, varias seguidas mientras los bots le disparan
			jugador.global_position += Vector3(-3.0, 0, 0)
			var d: Vector3 = z.global_position - jugador.global_position
			jugador.set("look", Vector2(atan2(-d.x, -d.z), 0.05))
			jugador.rotation.y = atan2(-d.x, -d.z)
			for k in 6:
				await get_tree().create_timer(0.35).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(String(f).substr(12) % k)
	var t := 0.0
	while t < 12.0 and is_instance_valid(z) and not bool(z.muerta):
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	var muerto: bool = not is_instance_valid(z) or bool(z.muerta)
	print("[aliados] zombi: %s en %.1f s" % ["MUERTO" if muerto else "VIVO", t])
	ok = ok and muerto
	jugador.health = 30.0
	jugador.health_changed.emit(30.0)
	t = 0.0
	while t < 16.0 and float(jugador.health) < 99.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print("[aliados] vida del jugador: %.0f tras %.1f s · botiquines de los bots %s" % [float(jugador.health), t, str(bots.map(func(b): return b.tiene_botiquin))])
	ok = ok and float(jugador.health) >= 99.0
	# LOS ZOMBIS TAMBIEN VAN A POR ELLOS: un zombi junto a un bot, lejos del jugador, tiene que elegirle
	var b0: Node3D = bots[0]
	jugador.global_position += Vector3(0, 0, 25.0)
	b0.global_position = jugador.global_position + Vector3(0, 0, -24.0)
	_sacar("zombi", b0.global_position + Vector3(2.0, 0.2, 0.0))
	var z2 = _vivos.back()
	z2.despertar(false)
	await get_tree().create_timer(0.6).timeout
	var va: bool = z2._objetivo_actual() == b0
	print("[aliados] el zombi junto al bot va a por %s" % ("EL BOT" if va else "otro"))
	ok = ok and va
	var vida0: float = b0.health
	b0.take_damage(30.0)
	print("[aliados] el bot recibe 30 de un zombi: %.0f -> %.0f" % [vida0, b0.health])
	ok = ok and b0.health < vida0
	var h0: int = int(b0.hueco)
	b0.take_damage(500.0)
	await get_tree().create_timer(0.5).timeout
	# MUERE DE VERDAD: se va, deja un cuerpo con fisica que se puede revivir, y su plaza no se repone sola
	var b0_muerto: bool = not is_instance_valid(b0) and aliados_muertos.has(h0)
	var cuerpo: Node3D = null
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and int(c.get_meta("aliado_hueco", -1)) == h0:
			cuerpo = c
	print("[aliados] con 0 de vida el bot muere: %s · cuerpo %s · ragdoll %s" % [str(b0_muerto), str(cuerpo != null),
		str(cuerpo != null and cuerpo.has_meta("ragdoll"))])
	ok = ok and b0_muerto and cuerpo != null
	await get_tree().create_timer(4.0).timeout
	var n_bots: int = get_tree().get_nodes_in_group("aliados_pve").size()
	print("[aliados] 4 s despues sigue muerto (bots %d, no se repone solo)" % n_bots)
	ok = ok and aliados_muertos.has(h0)
	var rs = get_tree().current_scene.get("rescate")
	if rs and cuerpo:
		rs._escanear()
		var clave := "b%d" % int(cuerpo.get_meta("rescate_red_id"))
		var ve: bool = rs._vigente(clave)
		print("[aliados] el rescate ve el cuerpo (botones): %s" % str(ve))
		ok = ok and ve
		rs._revivir(clave, cuerpo.global_position)
		await get_tree().create_timer(0.5).timeout
		var vuelto: bool = not aliados_muertos.has(h0) and get_tree().get_nodes_in_group("aliados_pve").any(func(b): return int(b.hueco) == h0)
		print("[aliados] RCP: vuelve el mismo bot: %s" % str(vuelto))
		ok = ok and vuelto
	# otra vez muerto, y ahora vuelve con el refugio
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if int(b.hueco) == h0:
			b.take_damage(500.0)
	await get_tree().create_timer(0.3).timeout
	_revivir_caidos()
	await get_tree().create_timer(2.0).timeout
	var ref: bool = not aliados_muertos.has(h0) and get_tree().get_nodes_in_group("aliados_pve").any(func(b): return int(b.hueco) == h0)
	var restos := 0
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and not c.is_queued_for_deletion() and String(c.get_meta("rescate_team", "")) == "pve":
			restos += 1
	print("[aliados] refugio: vuelve %s · cuerpos que quedan %d" % [str(ref), restos])
	ok = ok and ref and restos == 0
	print("[aliados] %s" % ("TODO BIEN" if ok else "FALLA"))



## --aliadoslan (en las dos copias del banco LAN): cuantos compañeros bot hay en cada maquina
func _aliados_lan() -> void:
	for i in 6:
		await get_tree().create_timer(5.0).timeout
		var copias := 0
		for e in contenedor.get_children():
			if is_instance_valid(e) and "team" in e and String(e.team) == "pve":
				copias += 1
		print("[aliadoslan] %s: personas %d · bots con cerebro %d · bots en escena %d · disparos de bots recibidos %d" % ["anfitrion" if Net.hosting else "invitado",
			Net.player_count(), get_tree().get_nodes_in_group("aliados_pve").size(), copias, int(get_tree().current_scene.get("red_tiros_bot"))])
		if Net.hosting and i == 1 and is_instance_valid(jugador):
			for k in 3:
				_sacar("zombi", jugador.global_position + Vector3(10.0 + k, 0.2, 2.0 * k))
				if _vivos.back().has_method("despertar"):
					_vivos.back().despertar(false)



## INVITADO: una criatura del anfitrion agarra (o suelta) a alguien. Si soy yo, me inmovilizo; en todo caso su
## copia pinta la lengua o se sube encima
func _agarre_de_red(id: int, peer: int, modo: String) -> void:
	var c = _remotas.get(id)
	if c == null or not is_instance_valid(c):
		return
	if modo.begins_with("lanza"):
		if c.has_method("lengua_red"):
			c.lengua_red(modo)            # la lengua del fumador en vuelo: de adorno, el agarre lo decide el anfitrion
		return
	var yo: int = multiplayer.get_unique_id()
	var victima: Node3D = jugador if peer == yo else Net.remotes.get(peer)
	if peer < 0:
		# un compañero bot del anfitrion: su copia en esta maquina
		var copias = get_tree().current_scene.get("_bots_copia")
		victima = copias.get(-peer) if copias is Dictionary else null
	if c.has_method("agarre_visual"):
		c.agarre_visual(victima, modo)
	if peer == yo and is_instance_valid(jugador) and jugador.has_method("agarrado_por"):
		jugador.agarrado_por(c if modo != "" else null, modo)


func _bilis_de_red(segundos: float) -> void:
	if is_instance_valid(jugador) and jugador.has_method("bilis"):
		jugador.bilis(segundos)


## --especialestest (con --map=campana_huida --pve --sinaliados): cada especial de Left 4 Dead 2 delante del
## jugador. Tiene que hacer lo suyo (agarrar de su forma, vomitar, enfurecerse) y, a los que agarran, hacerles
## el daño de `agarre_suelta` tiene que soltarte
func prueba_especiales() -> void:
	await get_tree().create_timer(5.0).timeout
	jugador.set("invulnerable", true)
	var base := Vector3(70.0, 1.3, 41.0)
	var fallos: Array = []
	for caso in [["cazador", 9.0, "tirado"], ["fumador", 12.0, "lengua"], ["jinete", 6.0, "jinete"],
			["cargador", 12.0, "cargado"], ["tanque", 3.0, "estrangulado"], ["gordo", 3.5, "bilis"], ["bruja", 2.5, "bruja"]]:
		for c in _vivos:
			if is_instance_valid(c):
				c.queue_free()
		_vivos.clear()
		await get_tree().process_frame
		if jugador.has_method("soltar_agarre"):
			jugador.soltar_agarre()
		if "fase" in self:
			set("fase", "refugio")                 # sin director: solo el de la prueba
		jugador.global_position = base
		jugador.set("look", Vector2(-PI / 2, 0.0))
		jugador.rotation.y = -PI / 2
		jugador.set("_bilis_t", 0.0)
		var t: String = caso[0]
		_sacar(t, base + Vector3(float(caso[1]), -0.1, 0.0))
		var c = _vivos.back()
		if c.has_method("despertar"):
			c.despertar(false)
		var visto := ""
		var tiempo := 0.0
		while tiempo < 25.0:
			await get_tree().create_timer(0.25).timeout
			tiempo += 0.25
			if not is_instance_valid(c):
				break
			var m := String(jugador.get("agarre_modo"))
			if caso[2] == "bilis" and float(jugador.get("_bilis_t")) > 0.0:
				visto = "bilis"
				break
			if caso[2] == "bruja" and int(c.get("_bruja_estado")) == 3:
				visto = "bruja furiosa"
				break
			if m != "" and visto == "":
				visto = m
				if caso[2] == "cargado":
					continue                         # que siga: tiene que acabar machacando
				break
			if caso[2] == "cargado" and m == "machacado":
				visto += " -> machacado"
				break
		for fa in OS.get_cmdline_user_args():
			if String(fa).begins_with("--fotoagarre=") and String(jugador.get("agarre_modo")) != "":
				await get_tree().create_timer(1.2).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/agarre_%s.png" % [String(fa).substr(13), t])
				var cc = jugador.get("_cam_cine")
				if cc != null and is_instance_valid(cc) and is_instance_valid(c):
					print("[especiales]   camara a %.1f m del %s (alto %.1f) y a %.1f m de ti" % [
						Vector2(cc.global_position.x - c.global_position.x, cc.global_position.z - c.global_position.z).length(),
						t, float(c.datos.get("alto", 1.8)), cc.global_position.distance_to(jugador.global_position)])
		var suelta := "-"
		if String(jugador.get("agarre_modo")) != "" and is_instance_valid(c):
			c.take_damage(float(c.datos.get("agarre_suelta", 60.0)) + 5.0)
			await get_tree().create_timer(0.6).timeout
			suelta = "SUELTA" if jugador.get("agarre") == null else "NO SUELTA"
			if jugador.get("agarre") != null:
				fallos.append(t + " no suelta")
		var bien: bool = visto.begins_with(caso[2]) or (caso[2] == "bruja" and visto != "")
		if not bien:
			fallos.append(t)
		print("[especiales] %-9s %s en %.1f s · %s" % [t, visto if visto != "" else "NADA", tiempo, suelta])
	print("[especiales] %s" % ("TODO BIEN" if fallos.is_empty() else "FALLA: " + ", ".join(fallos)))



## --agarrelan (en las dos copias del banco LAN): un cazador y un fumador del anfitrion agarran al INVITADO; el
## invitado cuenta como se ve (inmovilizado y de que forma) y que le sueltan al hacerles daño
func _agarre_lan() -> void:
	await get_tree().create_timer(18.0).timeout
	if Net.hosting:
		jugador.set("invulnerable", true)
		jugador.global_position += Vector3(60.0, 0.0, 0.0)          # lejos: que vayan a por el invitado
		if "fase" in self:
			set("fase", "refugio")
		for t in ["cazador", "fumador"]:
			var r = Net.remotes.values()[0] if not Net.remotes.is_empty() else null
			if r == null:
				print("[agarrelan] sin invitado"); return
			_sacar(t, (r as Node3D).global_position + Vector3(8.0, 0.2, 0.0))
			var c = _vivos.back()
			c.despertar(false)
			await get_tree().create_timer(6.0).timeout
			print("[agarrelan] anfitrion: %s tiene a alguien: %s (%s)" % [t, str(c._agarrando != null), c._agarre_modo])
			c.take_damage(200.0)
			await get_tree().create_timer(3.0).timeout
	else:
		for i in 22:
			await get_tree().create_timer(1.0).timeout
			print("[agarrelan] invitado: agarrado %s" % String(jugador.get("agarre_modo")))



## --agarrebotstest (con --map=campana_huida --pve): un especial agarra a un compañero bot (el jugador, lejos) y
## los otros dos bots le disparan hasta soltarlo
func _agarre_bots_prueba() -> void:
	await get_tree().create_timer(6.0).timeout
	jugador.set("invulnerable", true)
	var fallos: Array = []
	for t in ["cazador", "fumador", "jinete", "tanque"]:
		for c in _vivos:
			if is_instance_valid(c):
				c.queue_free()
		_vivos.clear()
		if "fase" in self:
			set("fase", "refugio")
		var bots: Array = get_tree().get_nodes_in_group("aliados_pve")
		if bots.size() < 3:
			print("[agarrebots] faltan bots"); return
		jugador.global_position = Vector3(70.0, 1.3, 41.0)
		for b in bots:
			b.teletransportar_a(jugador)
			if b.has_method("soltar_agarre"):
				b.soltar_agarre()
			b.health = 100.0
		await get_tree().create_timer(1.0).timeout
		var b0 = bots[0]
		# el jugador un poco por detras de los bots: ellos se quedan quietos y el bicho, que sale por delante,
		# tiene mas cerca a un bot
		jugador.global_position = Vector3(64.0, 1.3, 41.0)
		await get_tree().create_timer(1.5).timeout
		var mas_x: Node3D = bots[0]
		for b in bots:
			if b.global_position.x > mas_x.global_position.x:
				mas_x = b
		_sacar(t, mas_x.global_position + Vector3(9.0 if t != "tanque" else 3.0, 0.2, 0.0))
		var c = _vivos.back()
		c.despertar(false)
		c.vida = 50000.0             # que no lo maten antes de saltar: aqui se mide el agarre, no la punteria
		CriaturaScript.eventos.clear()
		c._obsesiva = true            # va a por ESE bot (se mide si agarra bots, no a quien elige)
		c._presa = mas_x
		var agarrado := ""
		var tiempo := 0.0
		while tiempo < 25.0 and agarrado == "":
			await get_tree().create_timer(0.25).timeout
			tiempo += 0.25
			for b in bots:
				if is_instance_valid(b) and str(b.get("agarre_modo")) not in ["", "<null>"]:
					agarrado = "%s agarra a %s (%s) en %.1f s" % [t, b.bot_name, b.agarre_modo, tiempo]
		if is_instance_valid(c):
			c.vida = float(c.datos.get("vida", 250.0))
		# la pose del brazo del agarrado MIENTRAS forcejea (para ver luego que no se queda asi)
		var presa_b = null
		var brazo_ag := Basis()
		for b in bots:
			if is_instance_valid(b) and str(b.get("agarre_modo")) not in ["", "<null>"]:
				presa_b = b
		if presa_b != null:
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(presa_b) and presa_b.avatar and presa_b.avatar.bone_idx.has("arm_upper_l"):
				brazo_ag = presa_b.avatar.skeleton.get_bone_global_pose(presa_b.avatar.bone_idx["arm_upper_l"]).basis.orthonormalized()
				var av0 = presa_b.avatar
				print("[agarrebots]   agarrado: procesa %s · forcejeo %s peso %.2f · limp %.2f · clip %s · visible %s" % [str(av0.is_processing()),
					str(av0.forcejeo), float(av0._forcejeo_w), float(av0.get("_limp_t")), str(av0.current_clip), str(av0.is_visible_in_tree())])
		# y los otros le disparan: tiene que acabar suelto
		var libre := false
		var t2 := 0.0
		while agarrado != "" and t2 < 20.0:
			await get_tree().create_timer(0.5).timeout
			t2 += 0.5
			var alguno := false
			for b in bots:
				if is_instance_valid(b) and str(b.get("agarre_modo")) not in ["", "<null>"]:
					alguno = true
			if not alguno:
				libre = true
				break
		if agarrado == "":
			print("[agarrebots]   eventos: ", CriaturaScript.eventos, " presa ", c._presa, " dist ", c.global_position.distance_to(mas_x.global_position))
			print("[agarrebots]   %s: muerto %s · objetivo %s · vida %.0f" % [t, str(not is_instance_valid(c) or c.muerta),
				str(c.jugador.name) if is_instance_valid(c) and is_instance_valid(c.jugador) else "-", c.vida if is_instance_valid(c) else 0.0])
		print("[agarrebots] %s · %s" % [agarrado if agarrado != "" else t + " NO AGARRA", ("liberado en %.1f s (%s)" % [t2, "muerto" if not is_instance_valid(c) or c.muerta else "vivo"]) if libre else "SIGUE AGARRADO"])
		if agarrado == "" or not libre:
			fallos.append(t)
		# Y EL MUÑECO VUELVE A SU SER: sin forcejeo, con el arma y los brazos donde los tiene uno que no ha pasado nada
		if libre:
			await get_tree().create_timer(1.2).timeout
			if presa_b != null and is_instance_valid(presa_b) and presa_b.avatar:
				var ahora_b: Basis = presa_b.avatar.skeleton.get_bone_global_pose(presa_b.avatar.bone_idx["arm_upper_l"]).basis.orthonormalized()
				var ang: float = rad_to_deg(Quaternion(brazo_ag).angle_to(Quaternion(ahora_b)))
				print("[agarrebots]   brazo del que agarraron: %.0f grados de diferencia con su postura de forcejeo" % ang)
				if ang < 8.0:
					fallos.append(t + " brazos congelados")
			for fa in OS.get_cmdline_user_args():
				if String(fa).begins_with("--fotobots=") and is_instance_valid(mas_x):
					var bb: Node3D = mas_x
					var fr: Vector3 = -bb.global_transform.basis.z
					jugador.global_position = bb.global_position + Vector3(fr.x, 0, fr.z).normalized() * 3.0
					jugador.look_at_point(bb.global_position + Vector3.UP * 1.1)
					await get_tree().create_timer(0.3).timeout
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("%s/suelto_%s.png" % [String(fa).substr(11), t])
			for b in bots:
				if not is_instance_valid(b) or b.avatar == null:
					continue
				var av = b.avatar
				var brazo := "-"
				if av.skeleton and av.bone_idx.has("arm_upper_l"):
					var g: Transform3D = av.skeleton.get_bone_global_pose(av.bone_idx["arm_upper_l"])
					brazo = "%.2f" % g.basis.y.normalized().y
				print("[agarrebots]   %s: agarre %s · forcejeo %s peso %.2f · arma %s · brazo_l.y %s · clip %s · aiming %s" % [b.bot_name,
					str(b.agarre != null), str(av.forcejeo), float(av._forcejeo_w), str(av.weapon_root.visible if av.weapon_root else null),
					brazo, str(av.current_clip), str(av.aiming)])
				if av.forcejeo or float(av._forcejeo_w) > 0.0 or b.agarre != null:
					fallos.append(t + " sin resetear")
	print("[agarrebots] %s" % ("TODO BIEN" if fallos.is_empty() else "FALLA: " + ", ".join(fallos)))



## --lenguatest: la lengua del fumador se ve venir. Quieto te atrapa; si te apartas al verla salir, falla
func prueba_lengua() -> void:
	await get_tree().create_timer(5.0).timeout
	jugador.set("invulnerable", true)
	if "fase" in self:
		set("fase", "refugio")
	var base := Vector3(70.0, 1.3, 41.0)
	var res: Array = []
	for esquiva in [false, true]:
		for c in _vivos:
			if is_instance_valid(c):
				c._soltar_agarre()
				c.queue_free()
		_vivos.clear()
		jugador.soltar_agarre()
		jugador.global_position = base
		_sacar("fumador", base + Vector3(15.0, -0.1, 0.0))
		var f = _vivos.back()
		f.despertar(false)
		var t := 0.0
		var salio := -1.0
		var agarra := false
		var fallo := false
		while t < 12.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if not is_instance_valid(f):
				break
			if salio < 0.0 and bool(f._lengua_vuela):
				salio = t
				if esquiva:
					jugador.global_position = base + Vector3(0.0, 0.0, 3.0)      # un paso largo al lado
			if f._lengua_recoge > 0.0:
				fallo = true
			if jugador.agarre != null:
				agarra = true
				break
			if esquiva and fallo:
				break
		var viaje: float = (t - salio) if agarra and salio >= 0.0 else -1.0
		print("[lengua] %s: sale a %.1f s · agarra %s%s · falla %s" % ["ESQUIVANDO" if esquiva else "QUIETO", salio,
			str(agarra), (" (vuela %.2f s)" % viaje) if viaje >= 0.0 else "", str(fallo)])
		res.append(agarra if not esquiva else (fallo and not agarra))
	print("[lengua] %s" % ("TODO BIEN" if res == [true, true] else "FALLA"))



## --animbotstest: que clip pone el compañero bot quieto, andando, corriendo y a sprint (lo que el ve el jugador)
func prueba_anim_bots() -> void:
	await get_tree().create_timer(8.0).timeout
	jugador.set("invulnerable", true)
	if "fase" in self:
		set("fase", "refugio")
	var bots: Array = get_tree().get_nodes_in_group("aliados_pve")
	if bots.is_empty():
		print("[animbots] NO HAY BOTS")
		return
	var b = bots[0]
	jugador.global_position = Vector3(70.0, 1.3, 41.0)          # la calle Olmo: recta a lo largo de X
	await get_tree().create_timer(4.0).timeout
	var fr := Vector3.RIGHT
	var ruta: Array = get("ruta") if get("ruta") is Array else []
	for caso in [["quieto", 0.0], ["andar", 1.8], ["correr", -3.8], ["sprint", 6.5]]:
		# el jugador avanza a ese paso (por la ruta si la hay) y el bot le sigue
		var clips := {}
		var vels: Array = []
		for i in 180:
			await get_tree().physics_frame
			var paso: float = float(caso[1]) * get_physics_process_delta_time()
			jugador.global_position += fr * paso
			if i > 60:
				var c := String(b.avatar.current_clip) if b.avatar else "?"
				clips[c] = int(clips.get(c, 0)) + 1
				vels.append(Vector2(b.velocity.x, b.velocity.z).length())
		vels.sort()
		print("[animbots] %-7s vel bot mediana %.1f m/s · clips %s" % [caso[0], float(vels[vels.size() / 2]), str(clips)])



## --cazabot (para probarlo a mano): cada 25 s un cazador sale delante y va a por uno de tus bots
func _cazabot(tipo_cb: String) -> void:
	await get_tree().create_timer(8.0).timeout
	while is_inside_tree():
		var bots: Array = get_tree().get_nodes_in_group("aliados_pve")
		if not bots.is_empty() and is_instance_valid(jugador):
			var b = bots[0]
			var fr: Vector3 = -jugador.global_transform.basis.z
			_sacar(tipo_cb, b.global_position + Vector3(fr.x, 0, fr.z).normalized() * (12.0 if tipo_cb == "fumador" else 8.0) + Vector3.UP * 0.2)
			var c = _vivos.back()
			c.despertar(false)
			c._obsesiva = true
			c._presa = b
			_mensaje("PRUEBA: un %s va a por %s" % [tipo_cb, String(b.bot_name)])
		await get_tree().create_timer(25.0).timeout
