extends Node
const CifraScript := preload("res://scripts/cifra.gd")
## LAS HABILIDADES EN LA PARTIDA (2026-09-28, pedido). Una sola equipada (Settings.habilidad; se elige en el lobby, en
## HABILIDADES: habilidades.gd). Se usa con [X] o con el boton de la esquina de arriba (boton_habilidad.gd). Cuatro:
##
##   invisible  10 s casi invisible: el muneco entero solo DISTORSIONA lo de detras (avatar_animator.set_invisible). Los
##              bots no te buscan salvo que les pases rozando (enemy.gd, criatura.gd). Disparar te delata. Recarga 30 s.
##   punetazo   se carga (0,85 s: el puno se enciende y tiembla) y se lanza al aire: la ONDA avanza 22 m hacia donde
##              miras abriendo un tunel que crece de 1,3 a 2,6 m de radio (Net.net_carve_beam por tramos) y revienta a
##              quien pille. Recarga 25 s.
##   salto      se salta a donde apunta la mira (hasta 40 m, en parabola: hay que calcular) y al caer se golpea el suelo:
##              la onda rompe hacia ARRIBA y a los LADOS (un anillo de tallados a media altura) y casi nada hacia abajo.
##              Recarga 18 s.
##   gancho     se dispara un garfio a donde apuntas (hasta 45 m) y tira de ti a toda velocidad. Salto: te sueltas.
##              Recarga 7 s.
##
## Todo se ve en tercera persona y en las otras maquinas: el gesto del muneco (avatar_animator.gesto), las piezas de la
## mano, la cuerda y las ondas llegan por Net.net_habilidad; el tallado va por Net.net_carve_beam, que ademas queda en
## el historial del que entra tarde. En las copias (net_player) este mismo script corre con `remoto = true` y solo pinta.
##
## LO QUE SE VE DEL PUÑETAZO Y DEL SALTO (2026-09-30, las laminas de concepto): efectos de cine en oro y voxels, todos en
## hab_fx.gd (un gestor por escena, nodos reutilizados). Aqui solo se dice CUANDO: la carga (cubos que orbitan el puño,
## arcos, luz, motas del suelo; el puño y el antebrazo de oro los pone el muñeco), el golpe (destello, haz, anillos que
## viajan con la onda, chispas, estallidos donde hay pared), el salto (estela, rayas al caer) y el golpe al suelo (grietas
## que brillan y anillos por el suelo). Al que lo hace, ademas, la CAMARA: se cierra al cargar, se clava un instante
## en el golpe y da el tiron (player.fov_habilidad), sacude, y en primera persona destello y rayas de velocidad. A los
## que estan cerca les tiembla la vista segun la distancia.
const AvatarScript := preload("res://scripts/avatar_animator.gd")
const HabFx := preload("res://scripts/hab_fx.gd")

## Lo que sale en el lobby (habilidades.gd) y en el boton de la partida
const LISTA := [
	{"id": "invisible", "nombre": "INVISIBLE", "icono": "invisible", "color": Color(0.45, 0.85, 1.0),
		"texto": "Te vuelves casi invisible: solo se ve una distorsión, como de cristal. Los bots no te persiguen. Disparar te delata."},
	{"id": "punetazo", "nombre": "PUÑETAZO", "icono": "puno", "color": Color(1.0, 0.55, 0.15),
		"texto": "Gritas, cargas el puño y golpeas al aire: la onda rompe todo a su paso. Pega fuerte cerca y cada vez menos al alejarse."},
	{"id": "salto", "nombre": "SALTO DEMOLEDOR", "icono": "salto", "color": Color(1.0, 0.82, 0.2),
		"texto": "Saltas adonde apunta la mira y al caer revientas el suelo: la onda rompe arriba y a los lados y pega más cuanto más cerca."},
	{"id": "gancho", "nombre": "GANCHO", "icono": "gancho", "color": Color(0.45, 1.0, 0.5),
		"texto": "Disparas un garfio y te lleva volando. Muévete a los lados mientras te lleva; salta para soltarte."},
]

## LOS NIVELES (2026-09-28, pedido: "que sean todas de nivel 1 y se mejoren con dinero; el nivel 10 es como estan
## ahora"). [nivel 1, nivel 10] de cada valor que sube; entre medias, en linea recta. El nivel de cada una: nivel().
const NIVEL_MAX := 10
const MEJORAS := {
	"invisible": {"dura": [4.0, 10.0], "recarga": [40.0, 30.0]},
	# el tunel: largo, radio al salir y al final; el dano, el de cerca (lejos baja hasta el 12 %)
	# (el DAÑO, 2026-09-30, pedido: "al nivel 10, el doble que un misil": el cohete hace 130 -> 260; el nivel 1, 120)
	"punetazo": {"largo": [8.0, 22.0], "r0": [0.8, 1.3], "r1": [1.3, 2.6], "dano": [120.0, 260.0], "recarga": [30.0, 25.0]},
	# el alcance del salto; la onda del golpe (radio del dano) y el tamaño de la corona de tallados
	"salto": {"alcance": [8.0, 22.0], "onda": [3.5, 6.5], "corona": [0.55, 1.0], "dano": [120.0, 260.0], "recarga": [22.0, 18.0]},
	"gancho": {"alcance": [18.0, 45.0], "vel": [28.0, 40.0], "recarga": [9.0, 6.0]},
}
## Lo que se enseña de cada una en el lobby: [valor, nombre, unidad]
const MUESTRA := {"invisible": [["dura", "DURACIÓN", "s"], ["recarga", "RECARGA", "s"]],
	"punetazo": [["largo", "ALCANCE", "m"], ["dano", "DAÑO", ""]],
	"salto": [["alcance", "ALCANCE", "m"], ["dano", "DAÑO", ""]],
	"gancho": [["alcance", "ALCANCE", "m"], ["vel", "VELOCIDAD", "m/s"]]}

const PUNO_GOLPE := 95.0 / 60.0   ## el impacto del clip de Blender (avatar_animator.PUNIO_IMPACTO): grito, carga y golpe
const ONDA_VEL := 34.0            ## m/s
## Lo que empuja la onda del puñetazo a quien pilla: lo mismo que el mazo (fwd * impulse 6 * 4). Sale volando.
const PUNO_EMPUJE := 24.0
## Y a los cascotes que arranca (m/s en la direccion del golpe): "con un poquito de fuerza, que se vea el impacto"
const PUNO_EMPUJE_ESCOMBRO := 7.0
const SALTO_SUBE_MAX := 6.0      ## lo mas alto sobre donde estas que se puede caer (un tejado bajo)
const GANCHO_VEL_GARFIO := 95.0
const GANCHO_LADO := 7.0          ## m/s de lado mientras tira (izquierda / derecha)


## CADA NIVEL ES UN ARTICULO DE LA TIENDA ("hab_<id>_<n>", n = 2..10): se compra como un arma (Settings.comprar: sin
## cuenta, en local; con cuenta, el servidor, que tiene su lista de precios en servidor/precios.json y cobra) y el nivel
## es el mas alto que tengas. Nivel 1 de salida, gratis.
const PRECIO_NIVEL := [0, 0, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500, 7000]


static func clave_nivel(id: String, n: int) -> String:
	return "hab_%s_%d" % [id, n]


static func precio_nivel(n: int) -> int:
	return int(PRECIO_NIVEL[clampi(n, 0, NIVEL_MAX)])


## El nivel de una habilidad (1..10). DESDE EL 2026-09-29 ES EL DEL PERSONAJE QUE LA TRAE (nivel_personaje.gd: "al
## subir de nivel el personaje sube tambien su habilidad"); ya no se compran niveles sueltos. Una habilidad que no trae
## ningun personaje se queda en el 1.
static func nivel(id: String) -> int:
	for p in NivelPersonaje.personajes():
		if String(p["habilidad"]) == id:
			return NivelPersonaje.nivel_habilidad(String(p["id"]))
	return 1


## Un dato para enseñar: "12 m", "8 s", "85"
static func texto_valor(id: String, clave: String, unidad: String, n: int) -> String:
	var v := valor(id, clave, n)
	var t := ("%.1f" % v) if absf(v - roundf(v)) > 0.05 and v < 20.0 else ("%d" % int(roundf(v)))
	return t + ((" " + unidad) if unidad != "" else "")


## Un valor de una habilidad a un nivel (por defecto, el suyo)
static func valor(id: String, clave: String, n: int = -1) -> float:
	var m: Dictionary = MEJORAS.get(id, {})
	if not m.has(clave):
		return 0.0
	if n < 1:
		n = nivel(id)
	var ab: Array = m[clave]
	return lerpf(float(ab[0]), float(ab[1]), float(clampi(n, 1, NIVEL_MAX) - 1) / float(NIVEL_MAX - 1))

## Los brazos de primera persona: las mismas duraciones que avatar_animator.GESTOS, en el marco de la camara
## (x derecha, y arriba, z adelante)
const FP := {
	# (al ritmo del clip de Blender: coge aire, GRITA con los brazos arriba -se ven asomar por arriba, temblando-, guardia,
	# el puno derecho atras y el izquierdo midiendo, y el golpe al centro de la pantalla en PUNO_GOLPE)
	"punetazo": [
		[0.00, Vector3(0.30, -0.60, 0.30), Vector3(0.02, -0.60, 0.30)],
		[0.22, Vector3(0.26, -0.66, 0.34), Vector3(-0.02, -0.66, 0.34)],
		# (2026-09-30: la otra mano, abajo y a un lado: con los guantes gordos de las skins nuevas tapaba media pantalla)
		[0.40, Vector3(0.44, 0.10, 0.34), Vector3(-0.34, -0.66, 0.30)],
		[0.66, Vector3(0.46, 0.13, 0.34), Vector3(-0.34, -0.66, 0.30)],
		[0.92, Vector3(0.44, 0.08, 0.36), Vector3(-0.30, -0.56, 0.34)],
		[1.07, Vector3(0.20, -0.22, 0.38), Vector3(-0.16, -0.36, 0.46)],
		[1.27, Vector3(0.30, -0.34, 0.22), Vector3(-0.14, -0.34, 0.50)],
		[1.52, Vector3(0.31, -0.35, 0.20), Vector3(-0.14, -0.33, 0.50)],
		[1.585, Vector3(0.08, -0.10, 0.82), Vector3(0.02, -0.30, 0.30)],
		[1.67, Vector3(0.08, -0.10, 0.84), Vector3(0.02, -0.32, 0.30)],
		[1.77, Vector3(0.10, -0.12, 0.76), Vector3(0.02, -0.34, 0.30)],
		[1.93, Vector3(0.22, -0.30, 0.45), Vector3(0.02, -0.45, 0.32)],
		[2.17, Vector3(0.30, -0.55, 0.30), Vector3(0.02, -0.58, 0.30)],
		[2.50, Vector3(0.30, -0.62, 0.30), Vector3(0.02, -0.62, 0.30)]],
	"salto": [
		[0.00, Vector3(0.30, -0.60, 0.30), Vector3(0.02, -0.60, 0.30)],
		[0.18, Vector3(0.34, -0.72, 0.12), Vector3(-0.04, -0.72, 0.12)],
		[0.28, Vector3(0.36, 0.00, 0.40), Vector3(-0.04, 0.00, 0.40)],
		[0.40, Vector3(0.30, 0.16, 0.30), Vector3(-0.10, -0.25, 0.50)],
		[0.47, Vector3(0.16, -0.55, 0.58), Vector3(-0.24, -0.45, 0.30)],
		[0.62, Vector3(0.16, -0.58, 0.55), Vector3(-0.24, -0.47, 0.30)],
		[1.20, Vector3(0.30, -0.62, 0.30), Vector3(0.02, -0.62, 0.30)]],
	"gancho": [
		[0.00, Vector3(0.30, -0.60, 0.30), Vector3(0.02, -0.60, 0.30)],
		[0.14, Vector3(0.20, -0.12, 0.60), Vector3(0.02, -0.45, 0.35)],
		[0.50, Vector3(0.30, -0.62, 0.30), Vector3(0.02, -0.62, 0.30)]],
	"invisible": [
		[0.00, Vector3(0.30, -0.60, 0.30), Vector3(0.02, -0.60, 0.30)],
		[0.20, Vector3(0.24, -0.30, 0.40), Vector3(0.04, -0.24, 0.42)],
		[0.32, Vector3(0.12, -0.21, 0.43), Vector3(0.04, -0.24, 0.42)],
		[0.45, Vector3(0.24, -0.30, 0.40), Vector3(0.04, -0.24, 0.42)],
		[0.75, Vector3(0.30, -0.62, 0.30), Vector3(0.02, -0.62, 0.30)]],
}

var player = null                  ## el jugador (player.gd) o, con `remoto`, su copia (net_player.gd)
var _g := 15.0                     ## la gravedad del jugador (player.GRAVITY)
var remoto := false
var tipo := ""
var recarga := 0.0                 ## segundos que faltan para poder usarla otra vez
var recarga_total := 1.0
## "" | "invisible" | "carga" | "salto" | "gancho_ida" | "gancho_tira"
var fase := ""
var invisible_t := 0.0
## LA ENERGIA DE LA INVISIBILIDAD (2026-10-03, pedido con la barra de Crysis: "debajo de la vida, unas barras de energia;
## al activar la habilidad se gasta con el tiempo y cuando te mueves gastas mas"). Sustituye a la recarga de 30-40 s: se
## puede volver invisible con ENERGIA_MIN, se gasta mientras dura (quieto poco, moviendose mucho mas: `gasto_energia`) y
## se acaba al llegar a 0; visible, vuelve sola tras ENERGIA_ESPERA. El nivel de la habilidad ("dura", 4-10 s) estira lo
## que aguanta. La dibuja barra_energia.gd, debajo de la vida.
const ENERGIA_BASE := 100.0        ## la energia a nivel 1 del personaje (y la medida de los gastos)
const ENERGIA_POR_NIVEL := 10.0    ## lo que sube la energia maxima con cada nivel del personaje (pedido): 200 a nivel 11
const ENERGIA_MIN := 20.0          ## lo que hace falta para volverse invisible
## LA RECARGA, MUY LENTA (2026-10-03, pedido: "la carga de energia es muy rapida, hacerla muy muy lenta para que tenga un
## balance"): era 14/s tras 1,2 s; ahora la barra entera de nivel 1 tarda ~33 s
const ENERGIA_REGEN := 3.0         ## por segundo, sin gastar (algo mas con la carta de enfriamiento)
const ENERGIA_ESPERA := 2.0        ## s sin gastar antes de que empiece a volver
const ENERGIA_VEL_REF := 5.0       ## m/s: moviendose a esta velocidad se gasta el "moverse" entero (corriendo, hasta x1,4)
var _c_energia = CifraScript.decimal("energia", ENERGIA_BASE)
var energia: float = ENERGIA_BASE:     ## cifrada en memoria (cifra.gd)
	get: return _c_energia.get_f()
	set(v): _c_energia.set_f(v)
var energia_max := ENERGIA_BASE    ## la de tu personaje: ENERGIA_BASE + ENERGIA_POR_NIVEL por nivel (se pone en _ready)
## EL SUPER SALTO (2026-10-03, pedido: "a nivel 4 del personaje, mantener el salto un segundo: un super salto que gasta la
## mitad de la energia y salta el triple"). La ventaja "super_salto" del Specter (nivel_personaje.gd); el salto lo lleva
## player.gd (_salto_carga), aqui solo si se puede y lo que cuesta.
const SUPER_SALTO_S := 1.0         ## lo que hay que mantener el salto
const SUPER_SALTO_ALTO := 3.0      ## veces la altura de un salto normal
var _energia_espera := 0.0
## EL BLINDAJE (2026-10-03, pedido: "al lado de la habilidad, otra: reduccion de daño; al recibir daño lo reduce pero gasta
## energia"): el modo armadura de Crysis. Se enciende y se apaga (tecla Z, boton_blindaje.gd); encendido, cada golpe que te
## llega (balas, golpes, explosiones: player.take_damage -> filtrar_dano) baja BLINDAJE_REDUCE y lo que te ahorra lo paga
## la ENERGIA (BLINDAJE_COSTE por punto). Sin energia se apaga solo. No va a la vez que la invisibilidad.
const BLINDAJE_REDUCE := [0.40, 0.60]   ## lo que rebaja, a nivel 1 y 10 de la habilidad
const BLINDAJE_COSTE := 1.2             ## energia por punto de daño que te ahorra (era 0,8; pedido: "nunca se me acaba")
const BLINDAJE_GASTO := 1.0             ## y lo que gasta por segundo solo por llevarlo puesto (pedido: "muy poquita, sutil")
var blindaje := false
var nano: Node = null              ## los efectos del nanotraje en tu pantalla (nanotraje_fx.gd): solo el de esta maquina
var invisible_total := 10.0        ## lo que dura esta vez (su nivel): la barra del velo
var _t := 0.0
var _vel := Vector3.ZERO
var _punto := Vector3.ZERO
var _salto_dur := 1.0
var _atascado_t := 0.0
var _pos_antes := Vector3.ZERO
# los brazos de primera persona
var _fp_gesto := ""
var _fp_t := -1.0
var _fp_pausa := 0.0
# lo que se ve en el mundo
var _cuerda: MeshInstance3D = null
var _garfio: Node3D = null
var _garfio_pos := Vector3.ZERO
var _mat_garfio := 4               ## de que es lo que muerde el garfio: el golpe suena a eso
var _ondas: Array = []             ## [efecto, origen, dir, recorrido, tallado_hasta, largo, r0, r1, dano, pillados, paredes]
var _fp_invis: Dictionary = {}     ## el arma de primera persona, invisible: id -> [malla, material, sombra]
# los efectos de cine (hab_fx.gd) y la camara del que lo hace
var _fx_carga := 0
var _fx_vuelo := 0
var _cam_golpe_t := -1.0           ## reloj del parón y el tiron de la camara tras el golpe (-1: nada)
var _cam_tiron := 0.0              ## grados que abre la camara al acabar el parón
var _cae_suena := false
## Las pruebas (main.gd) usan cualquier habilidad aunque no la traiga el personaje puesto
static var prueba_todas := false


static func datos(id: String) -> Dictionary:
	for d in LISTA:
		if String(d["id"]) == id:
			return d
	return {}


func _ready() -> void:
	if player != null and player.get_script() != null:
		_g = float((player.get_script() as Script).get_script_constant_map().get("GRAVITY", _g))
	if not remoto:
		# LA HABILIDAD LA TRAE EL PERSONAJE (nivel_personaje.gd): ya no se elige
		tipo = NivelPersonaje.habilidad_equipada()
		if datos(tipo).is_empty():
			tipo = "gancho"
		preparar_personaje()


## Lo que depende del personaje: la ENERGIA (crece con su nivel) y los efectos del nanotraje. Al empezar y cuando se
## cambia de personaje en plena partida (main._personaje_prueba)
func preparar_personaje() -> void:
	if remoto:
		return
	tipo = NivelPersonaje.habilidad_equipada()
	if datos(tipo).is_empty():
		tipo = "gancho"
	energia_max = ENERGIA_BASE + ENERGIA_POR_NIVEL * float(NivelPersonaje.nivel(NivelPersonaje.equipado()) - 1)
	energia = energia_max
	if usa_energia() and nano == null and not "--sinnanofx" in OS.get_cmdline_user_args():
		nano = preload("res://scripts/nanotraje_fx.gd").new()
		nano.player = player
		add_child(nano)


## ¿Se esta haciendo algo que ocupa las manos? (player.gd no dispara, ni recarga, ni cambia de arma, ni tira granadas)
func ocupado() -> bool:
	return _fp_t >= 0.0 or fase in ["carga", "salto", "gancho_ida", "gancho_tira", "salto_prep", "salto_golpe"]


## ¿Lleva la habilidad el movimiento del jugador? (player.gd llama a antes_de_mover / despues_de_mover)
func mueve() -> bool:
	return fase in ["salto", "gancho_tira", "carga", "salto_prep", "salto_golpe"]


func lista() -> bool:
	if usa_energia():
		return fase == "" and recarga <= 0.0 and energia >= ENERGIA_MIN
	return recarga <= 0.0 and fase == ""


## ¿Va con ENERGIA en vez de recarga? (la invisibilidad: el Specter)
func usa_energia() -> bool:
	return tipo == "invisible"


## Lo que gasta por segundo: [quieto, lo que se suma moviendose a ENERGIA_VEL_REF]. Con su nivel: quieto aguanta 2 x "dura"
## (8-20 s). MOVERSE GASTA LA MITAD QUE ANTES (2026-10-03, pedido: "moviendome se drena muy rapido, el doble de lento"):
## lo de moverse era 100 / "dura" y es la cuarta parte, asi que andando (5 m/s) se gasta la mitad que antes: a nivel 1,
## 18,75/s en vez de 37,5 (5,3 s en vez de 2,7) y corriendo a tope 21,25 en vez de 47,5. Quieto, igual.
func gasto_energia() -> Vector2:
	var d := maxf(1.0, valor("invisible", "dura"))
	return Vector2(ENERGIA_BASE / (2.0 * d), ENERGIA_BASE / (4.0 * d))


## El numero del boton mientras se recarga ("" con la energia: la barra ya lo dice)
func texto_recarga() -> String:
	return "" if usa_energia() else "%d" % ceili(recarga)


## La carta de REDUCCION DE ENFRIAMIENTO (cartas.gd, las ESPECIALES) y la ventaja del personaje: la recarga dura menos.
## Tope del 60 % para que nunca quede en nada.
static func factor_recarga() -> float:
	return 1.0 - clampf(Cartas.efecto("enfriamiento"), 0.0, 0.6)


func fraccion_recarga() -> float:
	if usa_energia():
		return 0.0 if energia >= ENERGIA_MIN else clampf(1.0 - energia / ENERGIA_MIN, 0.0, 1.0)
	return clampf(recarga / maxf(0.01, recarga_total), 0.0, 1.0)


## LA HABILIDAD SE CARGA CON EL TIEMPO Y, UN POCO, AL MATAR Y AL RECIBIR DAÑO (2026-09-30, pedido: "que este
## balanceado"). Una baja adelanta CARGA_BAJA de la barra entera (con 25 s de recarga, 2,5 s); perder 100 de vida,
## CARGA_DANO (3,75 s). Lo llaman player.carta_baja (cada baja) y player.take_damage.
const CARGA_BAJA := 0.10
const CARGA_DANO := 0.15

func cargar(frac: float) -> void:
	if not remoto and usa_energia() and frac > 0.0:
		energia = minf(energia_max, energia + frac * ENERGIA_BASE)     # las bajas y los golpes dan energia
		return
	if remoto or recarga <= 0.0 or frac <= 0.0:
		return
	recarga = maxf(0.0, recarga - frac * recarga_total)


# ================================================================== USAR
## El BLINDAJE: lo que rebaja con el nivel de la habilidad
func blindaje_reduccion() -> float:
	var n := clampi(nivel(tipo), 1, NIVEL_MAX)
	# y la ventaja de NV.7 del Specter: +5 % (nivel_personaje.gd, "blindaje_extra")
	return minf(0.9, lerpf(BLINDAJE_REDUCE[0], BLINDAJE_REDUCE[1], float(n - 1) / float(NIVEL_MAX - 1)) \
		+ Cartas.efecto("blindaje_extra"))


## ¿Puede hacer el SUPER SALTO? (la ventaja de NV.4 y la mitad de la energia)
func super_salto_listo() -> bool:
	return not remoto and usa_energia() and Cartas.efecto("super_salto") > 0.0 and energia >= energia_max * 0.5


func gastar_super_salto() -> void:
	energia = maxf(0.0, energia - energia_max * 0.5)
	_energia_espera = ENERGIA_ESPERA
	if nano != null:
		nano.salto()
	_traje_muneco("barrido")
	Net.net_habilidad("super_salto", [])


## La carga del super salto (0..1, player.gd mientras se mantiene) y el aterrizaje
func carga_super_salto(k: float) -> void:
	if nano != null:
		nano.carga_salto(k)


func aterriza_super_salto() -> void:
	if nano != null:
		nano.aterrizaje(1.0)


const VOZ_BLINDAJE_PROB := 0.08

## LOS SONIDOS DEL TRAJE DE CRYSIS (2026-10-03, pedido: "el de desactivar me lo generaste vos"): blindaje_off,
## invisible_on, invisible_off (sounds/crysis/traje, tools/importar_crysis_choques.py). Los de APAGAR son los de encender
## AL REVES (el paquete no trae de apagar; pedido: "el sonido inverso, de derecha a izquierda"). `mio`: el tuyo suena en
## ESTEREO sin posicion (el barrido de izquierda a derecha al encender, de derecha a izquierda al apagar); el de los
## demas, en 3D. Sin la carpeta, el generado de antes (`gen`).
func _sonido_traje(nombre: String, gen: String, db: float, alcance: float, mio: bool) -> void:
	if player == null:
		return
	if not Audio.traje(nombre, player.global_position, db, alcance, mio):
		Audio.play3d(gen, player.global_position, db, 0.0, alcance, Audio.PRI_MID)

## Encender o apagar el BLINDAJE (tecla Z, boton_blindaje.gd). false si no se puede.
func alternar_blindaje() -> bool:
	if remoto or player == null or not usa_energia():
		return false
	if blindaje:
		_fin_blindaje()
		return true
	if energia < 1.0 or float(player.get("health")) <= 0.0 or bool(player.get("spectating")):
		Audio.ui("atras", -12.0)
		return false
	if fase == "invisible":
		_fin_invisible()          # o una cosa o la otra
	blindaje = true
	# el traje de Crysis endureciendose (2026-10-03, pedido) y, solo VOZ_BLINDAJE_PROB de las veces (pedido: "que no se
	# escuche siempre, un 5-10 %"), la voz "Maximum Armor" (solo en tu maquina); sin la carpeta, los de antes
	if Audio.traje("blindaje", player.global_position, 0.0, 25.0, true):
		if randf() < VOZ_BLINDAJE_PROB:
			Audio.traje("voz_blindaje", player.global_position, -2.0, 10.0, true)
	else:
		Audio.play3d("gen/hab/listo", player.global_position, -2.0, 0.0, 15.0, Audio.PRI_MID)
		Audio.play3d("gen/hab/zumbido", player.global_position, -10.0, 0.0, 15.0, Audio.PRI_LOW)
	if nano != null:
		nano.blindaje_on(true)
	_traje_muneco("blindaje")
	Net.net_habilidad("blindaje", [])
	return true


## El brillo del traje en tu muñeco (el que ves en tercera persona y el de las copias de red lo pone recibir)
func _traje_muneco(que: String) -> void:
	var av = player.get("avatar") if player != null else null
	if av == null or not is_instance_valid(av):
		return
	match que:
		"blindaje":
			if av.has_method("set_blindaje"):
				av.set_blindaje(true)
		"blindaje_fin":
			if av.has_method("set_blindaje"):
				av.set_blindaje(false)
		"barrido":
			if av.has_method("traje_barrido"):
				av.traje_barrido(av.TRAJE_CIAN)


func _fin_blindaje() -> void:
	if not blindaje:
		return
	blindaje = false
	if player != null and not remoto:
		_sonido_traje("blindaje_off", "gen/hab/invisible_off", -6.0, 15.0, true)
		if nano != null:
			nano.blindaje_on(false)
		_traje_muneco("blindaje_fin")
		Net.net_habilidad("blindaje_fin", [])


## Lo que de verdad te quita un golpe (player.take_damage): con el BLINDAJE, menos, pagado con energia
func filtrar_dano(d: float) -> float:
	if not blindaje or remoto or d <= 0.0:
		return d
	var ahorro := minf(d * blindaje_reduccion(), energia / BLINDAJE_COSTE)
	if nano != null:
		var atacante = player.get("last_attacker")
		var desde := Vector3.ZERO
		if atacante != null and int(atacante) != 0 and Net.remotes.has(int(atacante)):
			desde = (Net.remotes[int(atacante)] as Node3D).global_position
		nano.golpe(desde, clampf(d / 60.0, 0.0, 0.7))
	energia = maxf(0.0, energia - ahorro * BLINDAJE_COSTE)
	_energia_espera = ENERGIA_ESPERA
	if energia <= 0.5:
		energia = 0.0
		_fin_blindaje()
	return d - ahorro


func activar() -> bool:
	if remoto or player == null:
		return false
	# LAS HABILIDADES SE CONSIGUEN EN EL PASE (pase_batalla.gd): sin reclamarla, no se usa
	if not PaseBatalla.habilidad_disponible(tipo) and not prueba_todas:
		return false
	# LA INVISIBILIDAD SE APAGA CON LA MISMA TECLA (2026-10-03, bug: "aprete la X para encenderla y la quise apagar con la
	# X y no paso nada": solo se cortaba al disparar o sin energia)
	if fase == "invisible" and usa_energia():
		_fin_invisible()
		return true
	if not lista() or ocupado():
		if recarga > 0.0:
			Audio.ui("atras", -12.0)
		return false
	if float(player.get("health")) <= 0.0 or bool(player.get("spectating")) or player.get("br_control") != null \
			or player.get("agarre") != null or float(player.get("caido_t")) > 0.0 or float(player.get("_trepa_t")) >= 0.0 \
			or (player.has_method("lanzando") and player.lanzando()):
		return false
	match tipo:
		"invisible":
			_fin_blindaje()           # o una cosa o la otra
			_empezar_invisible()
		"punetazo":
			_empezar_punetazo()
		"salto":
			return _empezar_salto()
		"gancho":
			return _empezar_gancho()
	return true


## Disparar te delata (player.fire)
func al_disparar() -> void:
	if fase == "invisible":
		_fin_invisible()


func al_morir() -> void:
	# el BLINDAJE se apaga DEL TODO (2026-10-03, bug: "muero y reaparezco con la habilidad activada": aqui solo se ponia
	# blindaje = false y se quedaban la lente, el brillo del traje y el aviso a los demas)
	_fin_blindaje()
	if fase == "invisible":
		_fin_invisible()
	if fase in ["gancho_ida", "gancho_tira"]:
		_fin_gancho(false)
	fase = ""
	_fp_t = -1.0
	_fp_fin()
	_fx_cortar()


## AL REAPARECER (player._respawn, por donde pasan todos los caminos de vuelta): nada encendido de la vida anterior
func al_reaparecer() -> void:
	_fin_blindaje()
	if fase == "invisible":
		_fin_invisible()
	if player != null:
		player.set("invisible", false)
		var av = player.get("avatar")
		if av and is_instance_valid(av):
			if av.has_method("set_invisible"):
				av.set_invisible(false)
			if av.has_method("set_blindaje"):
				av.set_blindaje(false)
	if nano != null:
		nano.apagar()


func _apuntar() -> Array:
	if player.has_method("_aim_ray"):
		return player._aim_ray(60.0)
	var c: Camera3D = player.get("cam")
	return [c.global_position, -c.global_transform.basis.z]


func _mundo():
	return player.get("world")


# ------------------------------------------------------------------ INVISIBLE
func _empezar_invisible() -> void:
	fase = "invisible"
	invisible_t = valor("invisible", "dura")
	invisible_total = invisible_t
	player.set("invisible", true)
	_gesto("invisible")
	_sonido_traje("invisible_on", "gen/hab/invisible_on", 0.0, 25.0, true)
	# el cuerpo propio (se ve en tercera persona y en los espejos): con mas filo, para saber donde esta uno
	var av = player.get("avatar")
	if av and is_instance_valid(av):
		av.set_invisible(true, true)
	# a los demas, sin fin: se acaba cuando llega "invisible_fin" (la energia puede durar mas que "dura")
	Net.net_habilidad("invisible", [9999.0])
	if nano != null:
		nano.invisible_on(true)


func _fin_invisible() -> void:
	if fase != "invisible":
		return
	fase = ""
	invisible_t = 0.0
	# con la ENERGIA no hay recarga larga: un segundo para no encenderla y apagarla sin querer
	recarga_total = 1.0 if usa_energia() else valor("invisible", "recarga") * factor_recarga()
	recarga = recarga_total
	_energia_espera = ENERGIA_ESPERA
	if not remoto:
		player.set("invisible", false)
		_fp_arma_invisible(false)
		if nano != null:
			nano.invisible_on(false)
		_sonido_traje("invisible_off", "gen/hab/invisible_off", 0.0, 25.0, true)
		Net.net_habilidad("invisible_fin", [])
	var av = player.get("avatar")
	if av and is_instance_valid(av):
		av.set_invisible(false)


## El arma de primera persona tambien (con mucho filo: tienes que ver donde apuntas)
func _fp_arma_invisible(on: bool) -> void:
	var piv = player.get("weapon_pivot")
	if on and piv and is_instance_valid(piv):
		var mat := AvatarScript.material_invisible(true)
		for mi in (piv as Node).find_children("*", "MeshInstance3D", true, false):
			var k := (mi as Object).get_instance_id()
			if _fp_invis.has(k):
				continue
			_fp_invis[k] = [mi, (mi as MeshInstance3D).material_override, (mi as MeshInstance3D).cast_shadow]
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not on:
		for k in _fp_invis.keys():
			var e: Array = _fp_invis[k]
			if is_instance_valid(e[0]):
				(e[0] as MeshInstance3D).material_override = e[1]
				(e[0] as MeshInstance3D).cast_shadow = e[2]
		_fp_invis.clear()


# ------------------------------------------------------------------ PUÑETAZO
func _empezar_punetazo() -> void:
	fase = "carga"
	_t = 0.0
	_gesto("punetazo")
	set_meta("grito", false)
	set_meta("carga_suena", false)
	set_meta("zumbido", false)
	_carga_fx()
	Net.net_habilidad("punetazo", [])


## LA CARGA DE ENERGIA (aqui y en las copias de red): los cubos salen con el grito y se meten en el puño en el golpe
func _carga_fx() -> void:
	var g = _gestor()
	if g == null:
		return
	g.carga_fin(_fx_carga)
	_fx_carga = g.carga(_fx_mano, _fx_pies, PUNO_GOLPE + 0.02, _fx_escala, 0.36)


func _golpe_punetazo() -> void:
	var a := _apuntar()
	var o: Vector3 = a[0]
	var d: Vector3 = (a[1] as Vector3).normalized()
	fase = ""
	recarga_total = valor("punetazo", "recarga") * factor_recarga()
	recarga = recarga_total
	var fuerza := [valor("punetazo", "largo"), valor("punetazo", "r0"), valor("punetazo", "r1"), valor("punetazo", "dano")]
	_lanzar_onda(o, d, true, fuerza)
	if player.has_method("add_shake"):
		player.add_shake(0.9)
	# LA CAMARA: se clava un instante (el "parón" del golpe, solo en la vista: el juego no se para) y da el tiron
	_cam_golpe_t = 0.0
	_cam_tiron = 18.0
	var g = _gestor()
	if g != null:
		var fp := not bool(player.get("third_person"))
		g.pantalla(0.4 if fp else 0.12, 1.0 if fp else 0.0, -1.0)
	var hud = player.get("hud")
	if hud != null and is_instance_valid(hud) and hud.has_method("onda_expansiva") and not bool(player.get("third_person")):
		hud.onda_expansiva(Vector2(0.5, 0.5), 1.0)
	# el retroceso: el golpe te echa un poco para atras
	if "velocity" in player:
		player.velocity -= Vector3(d.x, 0.0, d.z) * 3.0
	Net.net_habilidad("punetazo_golpe", [o, d, fuerza])


## La onda. Con `talla`, ademas va abriendo el tunel (solo el que golpea: lo manda a todos).
## `fuerza`: [largo, radio al salir, radio al final, dano de cerca] (su nivel; en las otras maquinas llega por la red)
func _lanzar_onda(o: Vector3, d: Vector3, talla: bool, fuerza: Array = []) -> void:
	if fuerza.size() < 4:
		fuerza = [valor("punetazo", "largo", NIVEL_MAX), valor("punetazo", "r0", NIVEL_MAX), valor("punetazo", "r1", NIVEL_MAX), 0.0]
	Audio.play3d("gen/hab/punetazo", o, 6.0, 0.0, 120.0, Audio.PRI_HIGH)
	Audio.play3d("gen/hab/anillo", o + d * 2.0, 2.0, 0.04, 80.0, Audio.PRI_HIGH)
	var largo := float(fuerza[0])
	# LA ONDA DE CHOQUE DE LA LAMINA (2026-09-30; antes, una rafaga de viento): destello, haz, anillos de cubos que viajan
	# con ella, chispas y, donde hay pared, un estallido de oro (hab_fx.onda). Las paredes se buscan ahora, con rayos a
	# lo largo del tunel: sale igual en todas las maquinas porque el mundo es el mismo.
	var paredes := _paredes(o, d, largo)
	var id := 0
	var g = _gestor()
	if g != null:
		g.carga_fin(_fx_carga)
		_fx_carga = 0
		var puno := _fx_mano()
		if puno.distance_to(o) > 2.0:
			puno = o + d * 0.7
		id = g.onda(o, d, puno, largo, float(fuerza[1]), float(fuerza[2]), ONDA_VEL, paredes, _viendo_desde_dentro())
	# A LOS DE CERCA LES TIEMBLA LA VISTA (el que golpea ya tiene la suya)
	if remoto:
		var yo = _jugador_local()
		if yo != null and yo.has_method("add_shake"):
			var c: Vector3 = yo.global_position + Vector3.UP * 1.4
			var h := clampf(d.dot(c - o), 0.0, largo)
			var dist := (o + d * h).distance_to(c)
			if dist < 14.0:
				yo.add_shake(0.55 * (1.0 - dist / 14.0))
	var marcas: Array = []
	for p in paredes:
		marcas.append([float(p), false])
	# (el ultimo: a quien ha pillado ya esta onda; cada uno, una vez)
	_ondas.append([id, o, d, 0.0, 0.0 if talla else largo + 1.0, largo, float(fuerza[1]), float(fuerza[2]), float(fuerza[3]), {}, marcas])


## A cuantos metros de `o` da la onda contra algo (hasta cuatro paredes, separadas al menos 2,5 m)
func _paredes(o: Vector3, d: Vector3, largo: float) -> Array:
	var w = _mundo_fx()
	var out: Array = []
	if w == null or not w.has_method("raycast"):
		return out
	var s := 0.6
	for i in 4:
		if s >= largo:
			break
		var r: Dictionary = w.raycast(o + d * s, d, largo - s)
		if not bool(r.get("hit", false)):
			break
		var dist := s + float(r.get("distance", 0.0))
		if out.is_empty() or dist - float(out.back()) > 2.5:
			out.append(dist)
		s = dist + 1.5
	return out


func _ondas_tick(dt: float) -> void:
	for i in range(_ondas.size() - 1, -1, -1):
		var e: Array = _ondas[i]
		var o: Vector3 = e[1]
		var d: Vector3 = e[2]
		var largo: float = e[5]
		var r0: float = e[6]
		var r1: float = e[7]
		var dano: float = e[8]
		var rec: float = float(e[3]) + ONDA_VEL * dt
		e[3] = rec
		var frente := o + d * (1.2 + rec)
		# el polvo que levanta a su paso (cada 5 m; tambien en las otras maquinas)
		if int(rec / 5.0) != int((rec - ONDA_VEL * dt) / 5.0) and rec < largo:
			_polvo(frente, 1.0)
		# DONDE DA CONTRA UNA PARED: la nube y el estallido (el oro lo pinta hab_fx)
		for m in e[10]:
			if not bool(m[1]) and rec + 0.6 >= float(m[0]):
				m[1] = true
				var pp: Vector3 = o + d * float(m[0])
				_polvo(pp, 1.8, 0.4)
				Audio.play3d("gen/hab/estallido", pp, 4.0, 0.06, 90.0, Audio.PRI_HIGH)
		# EL TUNEL: se talla en tramos de 3 m segun avanza (el que golpea lo manda a todos; queda en el historial)
		var hasta: float = e[4]
		if rec >= hasta + 3.0 or (rec >= largo and hasta < largo):
			var desde := hasta
			var fin := minf(rec, largo)
			e[4] = fin
			var w = _mundo()
			if w != null and fin > desde:
				var r := lerpf(r0, r1, clampf(fin / largo, 0.0, 1.0))
				# los cascotes y el polvo que arranca salen EMPUJADOS hacia donde va el golpe (pedido: "que se vea la fuerza")
				Net.net_carve_beam(w, o + d * (1.6 + desde), d, fin - desde, r, 255, false,
					d * PUNO_EMPUJE_ESCOMBRO + Vector3.UP * 1.5)
				# Y LO QUE PILLE: bots, criaturas y los demas jugadores (tu no: tu golpe no te hace dano). EL DANO SE APAGA
				# CON EL CAMINO (pedido): entero al salir del puno, un 12 % cuando la onda se muere
				var apaga := lerpf(1.0, 0.12, pow(clampf((desde + fin) * 0.5 / largo, 0.0, 1.0), 0.8))
				# EL QUE ESTE DENTRO DEL TUBO DEL TRAMO (con su cuerpo, no sus pies) se lleva el golpe UNA vez, y sale
				# VOLANDO hacia donde va el golpe con la fuerza del mazo (pedido). El primer tramo empieza en el puño.
				var ta := o + d * (0.6 if desde <= 0.0 else 1.6 + desde)
				Combat.damage_tubo(get_tree(), ta, o + d * (1.6 + fin), r + 0.9, dano * apaga, player,
					(d + Vector3.UP * 0.25).normalized() * PUNO_EMPUJE, e[9])
		# (lo que se ve lo acaba hab_fx por su cuenta)
		if rec >= largo + 1.0:
			_ondas.remove_at(i)


# ------------------------------------------------------------------ SALTO DEMOLEDOR
func _empezar_salto() -> bool:
	var a := _apuntar()
	var o: Vector3 = a[0]
	var d: Vector3 = (a[1] as Vector3).normalized()
	var desde: Vector3 = player.global_position
	var salto_max := valor("salto", "alcance")
	# EL DESTINO, DENTRO DE LO QUE SE SALTA (2026-09-28, "apunto al cielo y me manda hasta las nubes"): lo que se mira,
	# si esta a menos de salto_max en horizontal y no mas de SALTO_SUBE_MAX por encima; si no, el suelo que haya en esa
	# direccion a esa distancia (mirando al cielo, cerca: casi en el sitio)
	var plano := Vector3(d.x, 0.0, d.z)
	if plano.length() < 0.05:
		plano = -player.global_transform.basis.z
		plano.y = 0.0
	plano = plano.normalized()
	var destino := Vector3.INF
	var w = _mundo()
	var r: Dictionary = {}
	if w != null and w.has_method("raycast_con_piezas"):
		# (desde 1,5 m: un cascote pegado a la cara no es a donde se quiere saltar)
		r = w.raycast_con_piezas(o + d * 1.5, d, 60.0)
	if bool(r.get("hit", false)):
		var ph: Vector3 = r["position"]
		var hz := Vector2(ph.x - desde.x, ph.z - desde.z).length()
		if hz <= salto_max and ph.y - desde.y <= SALTO_SUBE_MAX:
			destino = ph - d * 0.6
	if destino == Vector3.INF:
		var lejos := salto_max
		if bool(r.get("hit", false)):
			var ph2: Vector3 = r["position"]
			lejos = clampf(Vector2(ph2.x - desde.x, ph2.z - desde.z).length(), 3.0, salto_max)
		else:
			# al cielo: cuanto mas arriba se mira, mas cerca (derecho arriba, un salto en el sitio)
			lejos = salto_max * clampf(Vector2(d.x, d.z).length() * 1.2 - 0.15, 0.1, 1.0)
		var p := desde + plano * lejos
		destino = p
		if w != null and w.has_method("raycast_con_piezas"):
			var rs: Dictionary = w.raycast_con_piezas(p + Vector3.UP * SALTO_SUBE_MAX, Vector3.DOWN, SALTO_SUBE_MAX + 40.0)
			if bool(rs.get("hit", false)):
				destino = rs["position"]
	destino.y = minf(destino.y, desde.y + SALTO_SUBE_MAX)
	var delta := destino - desde
	var horiz := Vector2(delta.x, delta.z).length()
	# EL ARCO, POR SU ALTURA: 2,2 m por encima del punto mas alto (de donde sales o de donde caes) y algo mas cuanto mas
	# lejos (hasta 4 m). De ahi salen la subida, la bajada y el tiempo; la velocidad en horizontal es la que cuadre.
	var g := _g
	var cima := maxf(0.0, delta.y) + minf(4.0, 2.2 + 0.08 * horiz)
	var vy := sqrt(2.0 * g * cima)
	var t := vy / g + sqrt(2.0 * maxf(0.05, cima - delta.y) / g)
	var v := Vector3(delta.x / t, vy, delta.z / t)
	# PRIMERO EL IMPULSO (0,2 s plantado: se agacha y coge fuerza) y LUEGO sale disparado, con la parabola ya calculada
	fase = "salto_prep"
	_t = 0.0
	_vel = v
	_salto_dur = t
	_gesto("salto", t + 3.0)
	# se agacha: un anillo de oro a los pies y unos cubos
	var gfx = _gestor()
	if gfx != null:
		gfx.impulso(desde, false)
	Net.net_habilidad("salto", [t])
	return true


func _despegar() -> void:
	fase = "salto"
	_t = 0.0
	_cae_suena = false
	Audio.play3d("gen/hab/salto", player.global_position, 2.0, 0.0, 40.0, Audio.PRI_HIGH)
	_polvo(player.global_position + Vector3.UP * 0.1, 0.9)
	_vuelo_fx(_salto_dur + 2.5)


## EL SALTO SE VE (aqui y en las copias): el anillo del despegue y la estela del puño; cayendo, las rayas
func _vuelo_fx(dur: float) -> void:
	var g = _gestor()
	if g == null:
		return
	g.impulso(player.global_position, true)
	g.vuelo_fin(_fx_vuelo)
	_fx_vuelo = g.vuelo(_fx_cuerpo, _fx_mano_vuelo, dur)


## Toca el suelo: el cuerpo al golpe (el puno revienta el suelo a los 0,12 s: _golpe_suelo) y plantado un momento
func _aterrizar() -> void:
	fase = "salto_golpe"
	_t = 0.0
	# se clava: la rodilla al suelo no resbala con lo que traia del vuelo
	player.velocity = Vector3(0.0, minf(0.0, player.velocity.y), 0.0)
	var av = player.get("avatar")
	if av and is_instance_valid(av) and av.has_method("salto_aterriza"):
		av.salto_aterriza()
	_soltar_gesto()
	var g = _gestor()
	if g != null:
		g.vuelo_fin(_fx_vuelo)
	_fx_vuelo = 0
	Net.net_habilidad("salto_cae", [player.global_position, valor("salto", "onda")])


func _golpe_suelo() -> void:
	var p: Vector3 = player.global_position
	recarga_total = valor("salto", "recarga") * factor_recarga()
	recarga = recarga_total
	var onda := valor("salto", "onda")
	var corona := valor("salto", "corona")
	_efecto_golpe_suelo(p, onda)
	if player.has_method("add_shake"):
		player.add_shake(1.0)
	if player.has_method("temblor_suelo"):
		player.temblor_suelo(0.08, 0.6)
	# la camara: el parón y el tiron, como el puñetazo pero mas corto; en primera persona, destello
	_cam_golpe_t = 0.0
	_cam_tiron = 12.0
	var g = _gestor()
	if g != null:
		var fp := not bool(player.get("third_person"))
		g.pantalla(0.45 if fp else 0.12, 0.6 if fp else 0.0, -1.0, true)
	var w = _mundo()
	if w != null:
		# HACIA ARRIBA Y A LOS COSTADOS: seis tallados en corona a 2,3 m, a media altura (su fondo queda a 10 cm del
		# suelo), y uno encima de la cabeza. Abajo, solo una grieta pequeña.
		# (la corona crece con el nivel: al 10, seis tallados de 1,55 m a 2,3 m; al 1, la mitad)
		# LOS CASCOTES SALEN VOLANDO hacia fuera y hacia arriba (2026-09-30, la lamina: "los bloques saltan"): el mismo
		# empuje que ya lleva el puñetazo (net_carve_beam), cada tallado hacia su lado. La forma del tallado no cambia.
		var rc := maxf(0.9, 1.55 * corona)
		for i in 6:
			var ang := i * TAU / 6.0
			var fuera := Vector3(cos(ang), 0.0, sin(ang))
			Net.net_carve_beam(w, p + Vector3(cos(ang) * 2.3 * corona, rc + 0.1, sin(ang) * 2.3 * corona), Vector3.UP, 1.2 * corona, rc, 255, false,
				fuera * 5.0 + Vector3.UP * 5.5)
		Net.net_carve_beam(w, p + Vector3.UP * (1.2 + 1.2 * corona), Vector3.UP, 1.4 * corona, maxf(1.0, 1.8 * corona), 255, false,
			Vector3.UP * 6.0)
		Net.net_carve_beam(w, p + Vector3.UP * 0.05, Vector3.UP, 0.1, 0.7, 120, false)
	var inv := bool(player.get("invulnerable"))
	player.set("invulnerable", true)
	# EL DANO BAJA CON LA DISTANCIA (damage_around ya lo reparte: entero en el centro, cero en el borde de la onda)
	Combat.damage_around(get_tree(), p + Vector3.UP * 0.8, onda, valor("salto", "dano"), player, true, true)
	player.set("invulnerable", inv)


## EL GOLPE AL SUELO (aqui y en las copias). `onda`: el radio del dano (los anillos llegan hasta ahi)
## (2026-09-30, la lamina: impacto dorado de cubos, grietas que brillan, anillos pixelados por el suelo y cascotes al
## rojo; antes, un toro naranja y una cupula que distorsionaba)
func _efecto_golpe_suelo(p: Vector3, onda: float = 6.5) -> void:
	Audio.play3d("gen/hab/golpe", p, 8.0, 0.0, 120.0, Audio.PRI_HIGH)
	var g = _gestor()
	var dentro := _viendo_desde_dentro()
	if g != null:
		g.golpe_suelo(p, onda, dentro)
	# (polvo si, humo poco: la nube negra de antes tapaba los cristales; desde dentro, menos: era una pared gris)
	_polvo(p + Vector3.UP * 0.3, 1.4 if dentro else 2.4, 0.0 if dentro else 0.6)
	# A LOS DE CERCA LES TIEMBLA EL SUELO (el que salta ya tiene lo suyo)
	if remoto:
		var yo = _jugador_local()
		if yo != null and yo.has_method("add_shake"):
			var dist: float = yo.global_position.distance_to(p)
			var alcance := onda * 4.0
			if dist < alcance:
				var k := 1.0 - dist / alcance
				yo.add_shake(0.6 * k)
				if yo.has_method("temblor_suelo"):
					yo.temblor_suelo(0.07 * k, 0.5)


# ------------------------------------------------------------------ GANCHO
func _empezar_gancho() -> bool:
	var a := _apuntar()
	var o: Vector3 = a[0]
	var d: Vector3 = (a[1] as Vector3).normalized()
	var esp: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + d * valor("gancho", "alcance"))
	q.exclude = [player.get_rid()]
	var r := esp.intersect_ray(q)
	var punto := o + d * valor("gancho", "alcance")
	var clava := false
	if not r.is_empty():
		punto = r["position"]
		clava = true
	else:
		var w = _mundo()
		if w != null and w.has_method("raycast_con_piezas"):
			var rv: Dictionary = w.raycast_con_piezas(o, d, valor("gancho", "alcance"))
			if bool(rv.get("hit", false)):
				punto = rv["position"]
				clava = true
	fase = "gancho_ida"
	_t = 0.0
	_punto = punto
	_garfio_pos = _mano()
	set_meta("clava", clava)
	_gesto("gancho", 99.0, punto)
	# SIN SONIDO AL DISPARAR NI AL TIRAR (pedido: "queda horrible"): solo el golpe al clavarse, el de un mazazo contra
	# lo que sea (Audio.hit con su material)
	_mat_garfio = 4
	var wm = _mundo()
	if wm != null and wm.has_method("raycast"):
		var rm: Dictionary = wm.raycast(o, d, valor("gancho", "alcance"))
		if bool(rm.get("hit", false)):
			_mat_garfio = int(rm.get("material", 4))
	Net.net_habilidad("gancho", [punto, _mat_garfio])
	return true


func _fin_gancho(con_impulso: bool) -> void:
	if not fase in ["gancho_ida", "gancho_tira"]:
		return
	var tiraba := fase == "gancho_tira"
	fase = ""
	recarga_total = valor("gancho", "recarga") * factor_recarga() if tiraba else 2.0
	recarga = recarga_total
	_soltar_gesto()
	if not remoto and con_impulso and "velocity" in player:
		# lo que llevaba, un poco menos, y un empujon hacia arriba para subirse al borde
		player.velocity = player.velocity * 0.55 + Vector3.UP * 4.5
	if not remoto:
		Net.net_habilidad("gancho_fin", [])


## La palma de la mano que dispara: la de los brazos de primera persona si te ves desde dentro, la del muneco si no
func _mano() -> Vector3:
	var tp := bool(player.get("third_person")) if player.get("third_person") != null else true
	var fa = player.get("fp_arms")
	if not remoto and not tp and fa and is_instance_valid(fa) and fa.has_method("mano_mundo"):
		return fa.mano_mundo(true)
	var av = player.get("avatar")
	if av and is_instance_valid(av) and av.has_method("mano_mundo"):
		return av.mano_mundo(true)
	return player.global_position + Vector3.UP * 1.3


# ================================================================== EL MOVIMIENTO (player.gd)
func antes_de_mover(dt: float) -> void:
	if fase == "salto_golpe":
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	elif fase in ["carga", "salto_prep"]:
		# gritando, cargando, cogiendo impulso o con la rodilla en el suelo no se anda: el clip planta los pies
		player.velocity.x = move_toward(player.velocity.x, 0.0, 30.0 * dt)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 30.0 * dt)
	elif fase == "salto":
		_vel.y -= _g * dt
		player.velocity = _vel
	elif fase == "gancho_tira":
		var hacia: Vector3 = _punto - player.global_position - Vector3.UP * 0.9
		var d: float = hacia.length()
		var quiere: Vector3 = hacia.normalized() * minf(valor("gancho", "vel"), 6.0 + d * 4.0)
		# DE LADO MIENTRAS SUBE (pedido): izquierda / derecha te desplazan hacia ese lado, perpendicular a la cuerda
		var mando: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var tactil = player.get("touch_move")
		if tactil is Vector2 and (tactil as Vector2).length() > 0.05:
			mando = tactil
		if absf(mando.x) > 0.1 and d > 2.0:
			var cam: Camera3D = player.get("cam")
			var der: Vector3 = cam.global_transform.basis.x if cam else player.global_transform.basis.x
			var lado := (der - hacia.normalized() * der.dot(hacia.normalized())).normalized()
			quiere += lado * GANCHO_LADO * clampf(mando.x, -1.0, 1.0)
		player.velocity = player.velocity.lerp(quiere, minf(1.0, 9.0 * dt))


func despues_de_mover(dt: float) -> void:
	if fase == "salto":
		_vel = player.velocity
		if (player.is_on_floor() and _t > 0.12) or _t > _salto_dur + 2.5 or bool(player.get("nadando")):
			_aterrizar()
	elif fase == "gancho_tira":
		var hacia: Vector3 = _punto - player.global_position - Vector3.UP * 0.9
		var movido: float = player.global_position.distance_to(_pos_antes)
		_pos_antes = player.global_position
		_atascado_t = _atascado_t + dt if movido < 2.0 * dt else 0.0
		if hacia.length() < 1.4 or _t > 3.0 or _atascado_t > 0.25:
			_fin_gancho(true)


# ================================================================== CADA CUADRO
func _physics_process(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# CON MUNICION INFINITA (el truco de probar, solo sin conexion), la habilidad tampoco espera: se puede apretar la X
	# sin parar (pedido)
	if recarga > 0.0 and not remoto and bool(player.get("municion_infinita")):
		recarga = 0.0
	if recarga > 0.0 and fase == "":
		recarga = maxf(0.0, recarga - dt)
		if recarga <= 0.0 and not remoto:
			Audio.play3d("gen/hab/listo", player.global_position, -6.0, 0.0, 8.0, Audio.PRI_MID)
	# el BLINDAJE puesto tambien gasta, muy poco, con el tiempo
	if not remoto and blindaje:
		energia -= BLINDAJE_GASTO * dt
		_energia_espera = ENERGIA_ESPERA
		if energia <= 0.0:
			energia = 0.0
			_fin_blindaje()
	# la ENERGIA vuelve sola mientras no gastas (ni invisible ni con el blindaje)
	if not remoto and usa_energia() and fase != "invisible" and not blindaje and energia < energia_max:
		_energia_espera -= dt
		if _energia_espera <= 0.0:
			energia = minf(energia_max, energia + ENERGIA_REGEN / factor_recarga() * dt)
	_t += dt
	match fase:
		"invisible":
			invisible_t -= dt
			if not remoto and usa_energia():
				# se gasta: quieto poco, moviendose mas (la velocidad de verdad del jugador, en el plano)
				var vel: Vector3 = player.get("velocity") if "velocity" in player else Vector3.ZERO
				var g := gasto_energia()
				energia -= (g.x + g.y * clampf(Vector2(vel.x, vel.z).length() / ENERGIA_VEL_REF, 0.0, 1.4)) * dt
				invisible_t = 9999.0
				if energia <= 0.0:
					energia = 0.0
					invisible_t = 0.0
			if not remoto:
				# el arma de primera persona, cuando el gesto ya ha terminado (antes la tapaban las manos)
				if _fp_t < 0.0 or _fp_t > 0.5:
					_fp_arma_invisible(true)
			if invisible_t <= 0.0:
				_fin_invisible()
		"salto_prep":
			if not remoto and _t >= AvatarScript.SALTO_IMPULSO:
				_despegar()
		"salto_golpe":
			if not remoto and _t >= AvatarScript.SALTO_IMPACTO and not bool(get_meta("golpeado", false)):
				set_meta("golpeado", true)
				_golpe_suelo()
			if _t >= 0.6:
				fase = ""
				set_meta("golpeado", false)
		"carga":
			if _t >= 0.34 and not bool(get_meta("grito", false)):
				set_meta("grito", true)
				Audio.play3d("gen/hab/grito", player.global_position + Vector3.UP * 1.5, 4.0, 0.03, 45.0, Audio.PRI_HIGH)
				# con el grito se levanta el polvo del suelo y empieza a subir la energia
				_polvo(player.global_position + Vector3.UP * 0.1, 1.1)
				if not remoto and player.has_method("add_shake"):
					player.add_shake(0.35)
			if _t >= 0.38 and not bool(get_meta("zumbido", false)):
				set_meta("zumbido", true)
				Audio.play3d("gen/hab/zumbido", player.global_position + Vector3.UP * 1.2, 0.0, 0.0, 40.0, Audio.PRI_HIGH)
			if _t >= 0.95 and not bool(get_meta("carga_suena", false)):
				set_meta("carga_suena", true)
				Audio.play3d("gen/hab/carga", player.global_position, 2.0, 0.0, 35.0, Audio.PRI_HIGH)
			if not remoto and _t >= PUNO_GOLPE:
				_golpe_punetazo()
		"gancho_ida":
			var hacia := _punto - _garfio_pos
			var paso := GANCHO_VEL_GARFIO * dt
			if hacia.length() <= paso:
				_garfio_pos = _punto
				if remoto:
					fase = "gancho_colgado"
					Audio.hit(_mat_garfio, _punto, 60)
				elif bool(get_meta("clava", false)):
					fase = "gancho_tira"
					_t = 0.0
					_atascado_t = 0.0
					_pos_antes = player.global_position
					Audio.hit(_mat_garfio, _punto, 60)
				else:
					_fin_gancho(false)
			else:
				_garfio_pos += hacia.normalized() * paso
		"gancho_tira":
			if not remoto and Input.is_action_just_pressed("jump"):
				_fin_gancho(true)
	_cuerda_tick()
	_ondas_tick(dt)
	if not remoto:
		_camara_tick(dt)
	# el cuerpo del muñeco mientras la cuerda tira (avatar_animator._aplicar_gancho_cuerpo): aqui y en las copias de red
	var av_g = player.get("avatar")
	if av_g and is_instance_valid(av_g) and "gancho_tira" in av_g:
		av_g.gancho_tira = fase in ["gancho_tira", "gancho_colgado"]
	if not remoto:
		_fp_tick(dt)
	else:
		_fp_reloj_copia(dt)


## En la copia: solo avanza el reloj del gesto (y la carga tiñe la pantalla de quien mira desde dentro)
func _fp_reloj_copia(dt: float) -> void:
	if fase == "carga" and _espectado_desde_dentro():
		var gp = _gestor()
		if gp != null:
			gp.pantalla(-1.0, -1.0, 0.45 * smoothstep(0.6, 1.5, _t))
	if _fp_t < 0.0 or not AvatarScript.GESTOS.has(_fp_gesto):
		return
	var g: Dictionary = AvatarScript.GESTOS[_fp_gesto]
	var pausa := float(g.get("pausa", -1.0))
	if pausa >= 0.0 and _fp_t >= pausa and _fp_pausa > 0.0:
		_fp_t = pausa
		_fp_pausa -= dt
	else:
		_fp_t += dt
	if _fp_t >= float(g["dur"]):
		_fp_t = -1.0


func _process(_dt: float) -> void:
	# la cuerda se pinta con la mano de ESTE cuadro (el muneco se mueve en _process)
	_cuerda_tick()


# ================================================================== LOS GESTOS
func _gesto(nombre: String, pausa: float = 0.0, punto: Vector3 = Vector3.ZERO) -> void:
	var av = player.get("avatar")
	if av and is_instance_valid(av) and av.has_method("gesto"):
		# el punetazo, con el clip de cuerpo entero hecho en Blender; si no esta, el gesto de IK
		if not (nombre == "punetazo" and av.has_method("punetazo_cuerpo") and av.punetazo_cuerpo()) \
				and not (nombre == "salto" and av.has_method("salto_cuerpo") and av.salto_cuerpo()):
			av.gesto(nombre, pausa, punto)
	_fp_empezar(nombre, pausa)


## El reloj del gesto de primera persona. Tambien en las copias de red: el espectador que mira desde sus ojos lo lee
## (player._animar_vista_esp) para mover SUS brazos.
func _fp_empezar(nombre: String, pausa: float = 0.0) -> void:
	_fp_gesto = nombre
	_fp_t = 0.0
	_fp_pausa = pausa


func _soltar_gesto() -> void:
	var av = player.get("avatar")
	if av and is_instance_valid(av) and av.has_method("soltar_gesto"):
		av.soltar_gesto()
	_fp_pausa = 0.0


## Los brazos de primera persona: las claves de FP delante de la camara (el gancho, apuntando al garfio), el arma
## abajo como al lanzar una granada (player._lanz_arma_w) y la pieza de la mano
func _fp_tick(dt: float) -> void:
	if _fp_t < 0.0:
		return
	var g: Dictionary = AvatarScript.GESTOS[_fp_gesto]
	var pausa := float(g.get("pausa", -1.0))
	if pausa >= 0.0 and _fp_t >= pausa and _fp_pausa > 0.0:
		_fp_t = pausa
		_fp_pausa -= dt
	else:
		_fp_t += dt
	var fa = player.get("fp_arms")
	var cam: Camera3D = player.get("cam")
	if _fp_t >= float(g["dur"]):
		_fp_t = -1.0
		_fp_fin()
		return
	var w := AvatarScript.gesto_pesos(_fp_gesto, _fp_t)
	player.set("_lanz_arma_w", w.y)
	if fa == null or not is_instance_valid(fa) or cam == null:
		return
	var m: Array = AvatarScript.lanzar_muestra(FP[_fp_gesto], _fp_t)
	var mg: Vector3 = m[0]
	var ma: Vector3 = m[1]
	if _fp_gesto == "gancho" and _punto != Vector3.ZERO:
		var hombro: Vector3 = cam.to_local(fa.hombro_mundo(true))
		var dl: Vector3 = cam.to_local(_punto).normalized()
		var brazo := hombro + dl * 0.62
		var k := smoothstep(0.0, 0.14, minf(_fp_t, 0.14)) * (1.0 - smoothstep(0.30, 0.50, _fp_t))
		mg = mg.lerp(Vector3(brazo.x, brazo.y, -brazo.z), k)
	fa.ver_brazos_fp = _fp_t > 0.04 and _fp_t < float(g["sale"][1]) - 0.02
	fa.agarrar_borde(Vector3(mg.x, mg.y, -mg.z), Vector3(ma.x, ma.y, -ma.z), w.x, cam, true)
	# (el salto tambien: el puño de oro en alto mientras vuela y hasta que revienta el suelo)
	fa.gesto_pieza = _fp_gesto if _fp_gesto in ["punetazo", "gancho", "salto"] else ""
	fa.gesto_pieza_t = _fp_t


func _fp_fin() -> void:
	if remoto or player == null:
		return
	player.set("_lanz_arma_w", 0.0)
	var fa = player.get("fp_arms")
	if fa and is_instance_valid(fa):
		fa.ver_brazos_fp = false
		fa.agarrar_borde(Vector3.ZERO, Vector3.ZERO, 0.0)
		fa.gesto_pieza = ""
		fa.gesto_pieza_t = -1.0


# ================================================================== LA RED: lo que ven los demas (net.gd)
func recibir(que: String, d: Array) -> void:
	var av = player.get("avatar")
	match que:
		"invisible":
			fase = "invisible"
			invisible_t = float(d[0]) if d.size() > 0 else valor("invisible", "dura", 1)
			invisible_total = invisible_t
			player.set("invisible", true)
			if av and is_instance_valid(av):
				av.gesto("invisible")
				av.set_invisible(true, false)
			_sonido_traje("invisible_on", "gen/hab/invisible_on", 0.0, 25.0, false)
		"invisible_fin":
			player.set("invisible", false)
			_fin_invisible()
			if av and is_instance_valid(av) and av.has_method("traje_barrido"):
				av.traje_barrido(av.TRAJE_CIAN)          # vuelve a verse con la franja de luz
		"blindaje":
			if av and is_instance_valid(av) and av.has_method("set_blindaje"):
				av.set_blindaje(true)
			if not Audio.traje("blindaje", player.global_position, -3.0, 25.0, false):
				Audio.play3d("gen/hab/listo", player.global_position, -4.0, 0.0, 20.0, Audio.PRI_MID)
		"blindaje_fin":
			if av and is_instance_valid(av) and av.has_method("set_blindaje"):
				av.set_blindaje(false)
			_sonido_traje("blindaje_off", "gen/hab/invisible_off", -6.0, 15.0, false)
		"super_salto":
			if av and is_instance_valid(av) and av.has_method("traje_barrido"):
				av.traje_barrido(av.TRAJE_CIAN)
			Audio.play3d("gen/hab/salto", player.global_position, -2.0, 0.0, 30.0, Audio.PRI_MID)
			_sonido_traje("invisible_off", "gen/hab/invisible_off", 0.0, 25.0, false)
		"punetazo":
			if av and is_instance_valid(av) and not (av.has_method("punetazo_cuerpo") and av.punetazo_cuerpo()):
				av.gesto("punetazo")
			_fp_empezar("punetazo")
			fase = "carga"
			_t = 0.0
			set_meta("grito", false)
			set_meta("carga_suena", false)
			set_meta("zumbido", false)
			_carga_fx()
		"punetazo_golpe":
			fase = ""
			_lanzar_onda(d[0], d[1], false, d[2] if d.size() > 2 else [])
			_pantalla_espectador(0.4, 1.0, true)
		"salto":
			if av and is_instance_valid(av) and not (av.has_method("salto_cuerpo") and av.salto_cuerpo()):
				av.gesto("salto", float(d[0]) + 3.0)
			_fp_empezar("salto", float(d[0]) + 3.0)
			var g = _gestor()
			if g != null:
				g.impulso(player.global_position, false)
			var vuela := float(d[0]) if d.size() > 0 else 1.5
			get_tree().create_timer(AvatarScript.SALTO_IMPULSO).timeout.connect(func():
				if is_instance_valid(player):
					Audio.play3d("gen/hab/salto", player.global_position, 2.0, 0.0, 40.0, Audio.PRI_HIGH)
					_polvo(player.global_position + Vector3.UP * 0.1, 0.9)
					_vuelo_fx(vuela + 2.5))
		"salto_cae":
			if av and is_instance_valid(av):
				if av.has_method("salto_aterriza"):
					av.salto_aterriza()
				av.soltar_gesto()
			_fp_pausa = 0.0
			get_tree().create_timer(AvatarScript.SALTO_IMPACTO).timeout.connect(func(): _pantalla_espectador(0.45, 0.6, false, true))
			var g2 = _gestor()
			if g2 != null:
				g2.vuelo_fin(_fx_vuelo)
			_fx_vuelo = 0
			var donde: Vector3 = d[0]
			var onda_r: float = float(d[1]) if d.size() > 1 else 6.5
			get_tree().create_timer(AvatarScript.SALTO_IMPACTO).timeout.connect(func(): _efecto_golpe_suelo(donde, onda_r))
		"gancho":
			fase = "gancho_ida"
			_punto = d[0]
			_mat_garfio = int(d[1]) if d.size() > 1 else 4
			_garfio_pos = _mano()
			if av and is_instance_valid(av):
				av.gesto("gancho", 99.0, _punto)
			_fp_empezar("gancho", 99.0)
		"gancho_fin":
			fase = ""
			_fp_pausa = 0.0
			if av and is_instance_valid(av):
				av.soltar_gesto()


## El destello y la onda en la pantalla de quien mira desde sus ojos (lo que ve el que golpea)
func _pantalla_espectador(a: float, b: float, onda_hud: bool, cristal := false) -> void:
	if not _espectado_desde_dentro():
		return
	var g = _gestor()
	if g != null:
		g.pantalla(a, b, -1.0, cristal)
	var yo = _espectador_local()
	var hud = yo.get("hud") if yo != null else null
	if onda_hud and hud != null and is_instance_valid(hud) and hud.has_method("onda_expansiva"):
		hud.onda_expansiva(Vector2(0.5, 0.5), 1.0)
	if yo != null and yo.has_method("add_shake"):
		yo.add_shake(0.9)


# ================================================================== LO QUE SE VE
func _capa_fx() -> Node:
	var w = _mundo()
	if w != null and is_instance_valid(w):
		return w.get_parent() if w.get_parent() != null else w
	return player.get_parent()


func _cuerda_tick() -> void:
	var ver := fase in ["gancho_ida", "gancho_tira", "gancho_colgado"]
	if not ver:
		if _cuerda:
			_cuerda.visible = false
		if _garfio:
			_garfio.visible = false
		return
	if _cuerda == null:
		_cuerda = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		_cuerda.mesh = cm
		var mc := StandardMaterial3D.new()
		mc.albedo_color = Color(0.12, 0.13, 0.14)
		mc.emission_enabled = true
		mc.emission = Color(0.3, 1.0, 0.4)
		mc.emission_energy_multiplier = 0.6
		_cuerda.material_override = mc
		_cuerda.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_capa_fx().add_child(_cuerda)
		_garfio = _malla_garfio()
		_capa_fx().add_child(_garfio)
	var a := _mano()
	var b := _garfio_pos
	var dv := b - a
	var largo := dv.length()
	_cuerda.visible = largo > 0.05
	_garfio.visible = true
	_garfio.global_position = b
	if largo > 0.05:
		_cuerda.global_position = a + dv * 0.5
		_orientar(_cuerda, dv / largo)
		_cuerda.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_cuerda.scale = Vector3(1, largo, 1)
		_orientar(_garfio, dv / largo)


static func _malla_garfio() -> Node3D:
	var n := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.58, 0.6)
	metal.metallic = 0.9
	metal.roughness = 0.3
	var eje := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.22
	eje.mesh = cm
	eje.rotation.x = PI * 0.5
	eje.material_override = metal
	n.add_child(eje)
	for i in 3:
		var una := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 0.14)
		una.mesh = bm
		una.material_override = metal
		var ang := i * TAU / 3.0
		una.position = Vector3(cos(ang) * 0.06, sin(ang) * 0.06, -0.08)
		una.rotation = Vector3(-sin(ang) * 0.9, cos(ang) * 0.9, 0.0)
		n.add_child(una)
	return n


func _orientar(n: Node3D, d: Vector3) -> void:
	var arriba := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.97 else Vector3.RIGHT
	n.look_at(n.global_position + d, arriba)


## `mezcla`: sobre un fondo transparente (el visor del lobby) la suma no se ve; ahi va mezclado y encendido
static func _mat_aditivo(c: Color, mezcla: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if mezcla else BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Polvo y humo de los de siempre (effects.gd: los de las explosiones)
func _polvo(p: Vector3, tamano: float, humo: float = 0.0) -> void:
	var fx = player.get("effects")
	if fx == null and Net.game != null:
		fx = Net.game.get("effects")
	if fx == null or not is_instance_valid(fx):
		return
	if fx.has_method("dust"):
		fx.dust(p, tamano)
	if humo > 0.0 and fx.has_method("smoke"):
		fx.smoke(p, humo)


# ================================================================== LOS EFECTOS DE CINE (hab_fx.gd)
## El gestor de la escena: el mismo para el jugador y para todas las copias de red
func _gestor():
	var capa: Node = Net.game if Net.game != null and is_instance_valid(Net.game) else _capa_fx()
	return HabFx.de(capa)


## El mundo, tambien en las copias (net_player no lo lleva): para buscar las paredes de la onda
func _mundo_fx():
	var w = _mundo()
	if w == null and Net.game != null and is_instance_valid(Net.game):
		w = Net.game.get("world")
	return w if w != null and is_instance_valid(w) else null


## El jugador de ESTA maquina (a quien le tiembla la vista cuando otro golpea cerca)
func _jugador_local():
	if Net.game != null and is_instance_valid(Net.game):
		var yo = Net.game.get("player")
		if yo != null and is_instance_valid(yo) and float(yo.get("health")) > 0.0:
			return yo
	return null


func _viendo_desde_dentro() -> bool:
	if remoto:
		return _espectado_desde_dentro()
	return not remoto and not bool(player.get("third_person"))


## EL ESPECTADOR EN SUS OJOS (2026-10-02, pedido: "veo el puñetazo pero no las particulas"): si el jugador de esta maquina
## mira a este (su copia) desde sus ojos, con su arma en las manos (player._vista_espectador), los efectos se pintan como
## en la pantalla del que la lanza: la carga en MI puño de primera persona, el destello y la onda de la pantalla.
func _espectador_local():
	if Net.game != null and is_instance_valid(Net.game):
		var yo = Net.game.get("player")
		if yo != null and is_instance_valid(yo):
			return yo
	return null


func _espectado_desde_dentro() -> bool:
	if not remoto or player == null:
		return false
	var yo = _espectador_local()
	return yo != null and yo.get("spectate_target") == player and String(yo.get("_vista_esp_id")) != "" 		and bool(yo.get("spectating"))


## Lo que siguen los efectos cada fotograma (Callables: si este nodo se va, el efecto se acaba solo)
## El puño de oro (avatar_animator.puno_mundo: el brazo que pega); desde dentro, el de los brazos de primera persona
func _fx_mano() -> Vector3:
	if remoto and _espectado_desde_dentro():
		var fa_e = _espectador_local().get("fp_arms")
		if fa_e != null and is_instance_valid(fa_e) and fa_e.has_method("puno_mundo"):
			return fa_e.puno_mundo()
	var fa = player.get("fp_arms")
	if _viendo_desde_dentro() and fa != null and is_instance_valid(fa) and fa.has_method("puno_mundo"):
		return fa.puno_mundo()
	var av = player.get("avatar")
	if av != null and is_instance_valid(av) and av.has_method("puno_mundo"):
		return av.puno_mundo()
	return _mano()


func _fx_pies() -> Vector3:
	return player.global_position + Vector3.UP * 0.05


## En primera persona el puño esta a medio metro de la camara: los cubos, mas pequeños y mas cerca
func _fx_escala() -> float:
	return 0.36 if _viendo_desde_dentro() else 1.0


func _fx_cuerpo() -> Vector3:
	return player.global_position + Vector3.UP * 0.9


## La estela del salto sale del puño en alto; desde dentro, del cuerpo (el puño de primera persona esta en la cara)
func _fx_mano_vuelo() -> Vector3:
	return _fx_cuerpo() if _viendo_desde_dentro() else _fx_mano()


## Corta lo que este en marcha (al morir)
func _fx_cortar() -> void:
	if _fx_carga != 0 or _fx_vuelo != 0:
		var g = _gestor()
		if g != null:
			g.carga_fin(_fx_carga)
			g.vuelo_fin(_fx_vuelo)
	_fx_carga = 0
	_fx_vuelo = 0
	_cam_golpe_t = -1.0
	if not remoto and player != null and is_instance_valid(player):
		player.set("fov_habilidad", 0.0)


## LA CAMARA DEL QUE LO HACE: la carga la cierra poco a poco y la hace temblar, con el borde de oro; en el golpe se clava
## 0,06 s y da el tiron (se abre de golpe y vuelve sola: player.gd la devuelve a su sitio); cayendo del salto se abre
## segun lo deprisa que caes, con rayas de velocidad. Nada de esto toca Engine.time_scale (en red no se puede).
func _camara_tick(dt: float) -> void:
	if player == null or not ("fov_habilidad" in player):
		return
	var f := 0.0
	var g = _gestor()
	if fase == "carga":
		var k := smoothstep(0.9, 1.5, _t)
		f = -7.0 * k
		if _t > 0.9 and player.has_method("temblor_suelo"):
			player.temblor_suelo(0.015 + 0.035 * k, 0.15)
		if g != null:
			g.pantalla(-1.0, -1.0, (0.45 if _viendo_desde_dentro() else 0.2) * smoothstep(0.6, 1.5, _t))
	elif fase == "salto" and g != null and _fx_vuelo != 0:
		var cae: float = g.vuelo_caida(_fx_vuelo)
		var kc := clampf((cae - 4.0) / 14.0, 0.0, 1.0)
		f = 9.0 * kc
		if kc > 0.0:
			if not _cae_suena:
				_cae_suena = true
				Audio.play3d("gen/hab/descenso", player.global_position, -2.0, 0.0, 40.0, Audio.PRI_HIGH)
			if _viendo_desde_dentro():
				g.pantalla(-1.0, 0.75 * kc, 0.3 * kc, true)
	if _cam_golpe_t >= 0.0:
		_cam_golpe_t += dt
		if _cam_golpe_t < 0.06:
			f = -10.0
		else:
			_cam_golpe_t = -1.0
			f = 0.0
			var cam = player.get("cam")
			if cam != null and is_instance_valid(cam):
				(cam as Camera3D).fov = clampf((cam as Camera3D).fov + _cam_tiron * Settings.camera_feel, 20.0, 150.0)
	if nano != null:
		f += float(nano.fov_extra)
	player.set("fov_habilidad", f)


func _exit_tree() -> void:
	for n in [_cuerda, _garfio]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_fx_cortar()
