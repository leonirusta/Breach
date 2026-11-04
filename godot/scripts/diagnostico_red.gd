extends RefCounted
## ¿POR QUE NO LLEGAMOS AL SERVIDOR? (2026-10-01, pedido: "que haga pruebas y, si es el wifi o el router, que te diga
## que es lo que falla").
##
## Tres peticiones a la vez, y lo que devuelve cada una dice donde se corta:
##   a) http://connectivitycheck.gstatic.com/generate_204 (sin cifrar): la misma que usa Android para saber si una red
##      tiene internet. 204 = hay internet; otra respuesta = un PORTAL del wifi (pide entrar o aceptar en el navegador).
##   b) https://www.google.com/generate_204: si (a) llega y esta no, la red INTERCEPTA lo cifrado (certificado propio).
##   c) <servidor>/config: el nuestro. Si hay internet y esta no llega, la red BLOQUEA nuestro servidor (y como: nombre,
##      conexion o cifrado); si contesta 5xx, el fallo es NUESTRO.
## Antes, si el aparato tiene alguna direccion de red (sin ella no hay ni wifi ni datos). No se manda nada del jugador.
##
## Uso: `var d: Dictionary = await DiagnosticoRed.correr(nodo, Cuenta.url)` → {codigo, titulo, texto, culpa, ok}
##   culpa: "aparato" | "red" | "router" | "servidor" | "" (ok = el servidor SI contesta ahora)

const ESPERA := 7.0
const URL_PORTAL := "http://connectivitycheck.gstatic.com/generate_204"
const URL_CIFRADO := "https://www.google.com/generate_204"


static func hay_red_local() -> bool:
	for ip in IP.get_local_addresses():
		var s := String(ip)
		if s.begins_with("127.") or s == "::1" or s.begins_with("169.254.") or s.to_lower().begins_with("fe80"):
			continue
		return true
	return false


## Una peticion: {r: resultado de HTTPRequest, c: codigo HTTP}
static func _probar(padre: Node, url: String) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = ESPERA
	h.max_redirects = 0          # un portal responde con una redireccion: queremos verla, no seguirla
	padre.add_child(h)
	if h.request(url) != OK:
		h.queue_free()
		return {"r": HTTPRequest.RESULT_CANT_CONNECT, "c": 0}
	var res: Array = await h.request_completed
	h.queue_free()
	return {"r": int(res[0]), "c": int(res[1])}


static func _llego(p: Dictionary) -> bool:
	return int(p.r) == HTTPRequest.RESULT_SUCCESS or int(p.r) == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED


static func correr(padre: Node, servidor: String) -> Dictionary:
	if not hay_red_local():
		return _sale("SIN-RED", "No estás conectado a ninguna red",
			"El aparato no tiene ni wifi ni datos. Conéctate a un wifi o activa los datos móviles y vuelve a intentarlo.",
			"aparato")
	# las tres a la vez: lo que mas tarda es una que no contesta (ESPERA)
	var estado := {"n": 0}
	var a := {}
	var b := {}
	var c := {}
	var fin := func(): estado.n += 1
	(func(): a.merge(await _probar(padre, URL_PORTAL)); fin.call()).call()
	(func(): b.merge(await _probar(padre, URL_CIFRADO)); fin.call()).call()
	(func(): c.merge(await _probar(padre, servidor.trim_suffix("/") + "/config")); fin.call()).call()
	while int(estado.n) < 3:
		if not is_instance_valid(padre) or not padre.is_inside_tree():
			return _sale("CANCELADO", "", "", "")
		await padre.get_tree().process_frame
	print("[red] portal r=%d c=%d · cifrado r=%d c=%d · servidor r=%d c=%d" % [a.r, a.c, b.r, b.c, c.r, c.c])

	# EL NUESTRO CONTESTA: no hay nada roto (se cayo un momento)
	if _llego(c) and int(c.c) > 0 and int(c.c) < 500:
		var r := _sale("OK", "Ya responde", "El servidor vuelve a contestar.", "")
		r.ok = true
		return r
	var hay_internet := (_llego(a) and int(a.c) == 204) or (_llego(b) and int(b.c) == 204)
	# PORTAL: la de Android no da 204 sino una pagina o una redireccion
	if _llego(a) and int(a.c) != 204:
		return _sale("PORTAL-WIFI", "Este wifi pide iniciar sesión",
			"Estás conectado al wifi, pero la red te pide entrar o aceptar sus condiciones antes de dejarte usar " +
			"internet (pasa en facultades, bares, hoteles...). Abre el navegador, acepta lo que pida y vuelve.",
			"red")
	if not hay_internet:
		var sin_nombres: bool = int(a.r) == HTTPRequest.RESULT_CANT_RESOLVE and int(b.r) == HTTPRequest.RESULT_CANT_RESOLVE
		if sin_nombres:
			return _sale("SIN-DNS", "La red no tiene internet",
				"Estás conectado a una red, pero el router no resuelve las direcciones de internet (DNS): " +
				"normalmente el router ha perdido la conexión. Reinícialo o prueba con datos móviles.",
				"router")
		if _llego(a) and int(b.r) == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return _sale("CIFRADO-INTERCEPTADO", "Esta red intercepta las conexiones seguras",
				"Hay internet, pero la red se mete en las conexiones cifradas (filtros de empresa o de centros de " +
				"estudio) y el juego no puede fiarse de ella. Prueba con datos móviles u otro wifi.",
				"red")
		return _sale("SIN-SALIDA", "La red no tiene salida a internet",
			"Estás conectado a una red, pero no deja llegar a internet: el router está sin conexión o el proveedor " +
			"tiene un corte. Reinicia el router o prueba con datos móviles.",
			"router")
	# HAY INTERNET Y EL NUESTRO NO LLEGA
	if _llego(c) and int(c.c) >= 500:
		return _sale("SERVIDOR-CAIDO", "El fallo es nuestro",
			"Tu internet funciona bien: es nuestro servidor el que no está respondiendo ahora mismo. Ya estamos " +
			"en ello; prueba en unos minutos.",
			"servidor")
	match int(c.r):
		HTTPRequest.RESULT_CANT_RESOLVE:
			return _sale("BLOQUEO-NOMBRE", "Esta red bloquea el juego",
				"Tienes internet, pero esta red no deja encontrar nuestro servidor (un filtro del router o de la red, " +
				"típico de facultades, colegios y oficinas). Prueba con datos móviles u otro wifi.",
				"red")
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return _sale("BLOQUEO-CIFRADO", "Esta red bloquea el juego",
				"Tienes internet, pero esta red se mete en la conexión cifrada con nuestro servidor y el juego no " +
				"puede fiarse de ella. Prueba con datos móviles u otro wifi.",
				"red")
	return _sale("BLOQUEO-CONEXION", "Esta red bloquea el juego",
		"Tienes internet, pero esta red no deja conectar con nuestro servidor (un cortafuegos del router o de la " +
		"red). Prueba con datos móviles u otro wifi; si te pasa en tu casa, reinicia el router.",
		"red")


static func _sale(codigo: String, titulo: String, texto: String, culpa: String) -> Dictionary:
	return {"codigo": codigo, "titulo": titulo, "texto": texto, "culpa": culpa, "ok": false}
