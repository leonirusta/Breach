extends MultiplayerPeerExtension
## EL PUENTE (2026-10-01, pedido: "que se pueda jugar online con datos o en la facultad, sin salir nunca del plan gratis").
##
## La partida va directa por UDP (ENet) entre el anfitrion y cada invitado. Cuando ese camino no se abre (datos moviles,
## redes que bloquean), los dos se conectan por WebSocket al servidor (servidor/puente.js) y este reenvia los paquetes
## sin mirarlos. Para la partida NO CAMBIA NADA: es un MultiplayerPeer como el de ENet, asi que las mismas RPC de siempre
## (disparos, daño al mundo, posiciones...) viajan igual; cada maquina sigue haciendo su fisica y su destruccion.
##
## DOS MODOS:
##   - invitado (`como_invitado`): todo por el WebSocket; su numero se lo da el servidor.
##   - anfitrion (`como_anfitrion`): ENVUELVE al ENet de siempre. Los invitados directos siguen por ENet y los del puente
##     por el WebSocket, en la MISMA partida. El WebSocket solo se abre cuando un invitado lo pide (el latido de la sala
##     trae `puente: true`, salas_online.gd) y se cierra solo cuando ya no queda nadie por el (cada minuto abierto cuesta).
##
## AHORRO (la salida de datos gratis del servidor es 1 GiB al mes):
##   - los paquetes de cada fotograma van JUNTOS en un solo mensaje (ENet manda uno por RPC, cada uno con sus cabeceras);
##   - el mensaje va COMPRIMIDO (zstd) si sale mas corto;
##   - el anfitrion manda UNA vez lo que es para todos y el servidor lo reparte;
##   - si el WebSocket va atascado (red mala), lo NO fiable (posiciones, que llegan otras enseguida) se tira en vez de
##     acumular retraso.
##
## Formato de un lote (lo que va despues de la cabecera del servidor): [banderas u8: bit0 = zstd][si zstd: tamaño u32]
## y luego, por paquete: [largo varint][canal << 2 | modo  u8][bytes].

const T_DATOS := 1
const T_ECHAR := 2
const T_ENTRA := 3
const T_SALE := 4
const T_HOLA := 5

const COMPRIMIR_DESDE := 96             ## lotes mas cortos van tal cual (zstd no gana nada)
const ATASCO := 48 * 1024               ## bytes por salir en el WebSocket a partir de los que se tira lo no fiable
const ANFITRION_SOLO_S := 30.0          ## el anfitrion cierra su WebSocket tras este rato sin nadie por el puente

var _ws: WebSocketPeer = null
var _ws_url := ""
var _enet: ENetMultiplayerPeer = null
var _anfitrion := false
var _mi_id := 0
var _estado := CONNECTION_DISCONNECTED
var _entrada: Array = []                ## [[de, canal, modo, PackedByteArray], ...]
var _target := 0
var _canal := 0
var _modo := TRANSFER_MODE_RELIABLE
var _rechazar := false
var _del_puente := {}                   ## anfitrion: id -> true de los invitados que vienen por el puente
var _lote := PackedByteArray()
var _lote_dest := 0
var _lote_hay := false
var _solo_t := 0.0
var _ws_listo := false
var motivo_cierre := ""                 ## por que se cerro el WebSocket (lo lee net.gd para decirlo)
var _bytes := [0, 0]                    ## mandados / recibidos por el WebSocket desde la ultima consulta (--medirtrafico)
## --medirtrafico: lo que se manda por el puente, por modo (fiable / no fiable / no fiable en orden): [paquetes, bytes]
var censo := {}
var _censo_crudo := 0                   ## bytes de los lotes antes de comprimir
var _censo_tirados := 0                 ## paquetes no fiables tirados por atasco


# ----------------------------------------------------------------------------------------------- montar
## Invitado: todo por el puente. `servidor` es Cuenta.url (https://...), `token` el de la cuenta.
func como_invitado(servidor: String, sala: String, token: String) -> Error:
	_anfitrion = false
	_estado = CONNECTION_CONNECTING
	_ws_url = "%s/puente?rol=invitado&sala=%s&t=%s" % [_a_ws(servidor), sala.uri_encode(), token.uri_encode()]
	return _abrir_ws()


## Anfitrion: el ENet de siempre por dentro. El WebSocket, solo cuando haga falta (`abrir_puente`).
func como_anfitrion(enet: ENetMultiplayerPeer) -> void:
	_anfitrion = true
	_enet = enet
	_mi_id = 1
	_estado = CONNECTION_CONNECTED
	_enet.peer_connected.connect(func(id: int): peer_connected.emit(id))
	_enet.peer_disconnected.connect(func(id: int): peer_disconnected.emit(id))


## Anfitrion: conectarse al puente de su sala (alguien espera). No hace nada si ya esta abierto.
func abrir_puente(servidor: String, sala: String, llave: String) -> void:
	if not _anfitrion or _ws != null:
		return
	_ws_url = "%s/puente?rol=anfitrion&sala=%s&k=%s" % [_a_ws(servidor), sala.uri_encode(), llave.uri_encode()]
	_solo_t = 0.0
	if _abrir_ws() == OK:
		print("[puente] anfitrion: abriendo el puente de la sala")


func enet() -> ENetMultiplayerPeer:
	return _enet


func en_puente() -> bool:
	return _ws != null


func es_del_puente(id: int) -> bool:
	return _del_puente.has(id)


func invitados_del_puente() -> int:
	return _del_puente.size()


func bytes_y_limpiar() -> Array:
	var b := _bytes.duplicate()
	_bytes = [0, 0]
	if not censo.is_empty():
		var nombres := {TRANSFER_MODE_RELIABLE: "fiable", TRANSFER_MODE_UNRELIABLE: "no fiable",
			TRANSFER_MODE_UNRELIABLE_ORDERED: "no fiable en orden"}
		var partes: Array = []
		for k in censo.keys():
			partes.append("%s %d paq / %.1f KB" % [nombres.get(k, str(k)), censo[k][0], censo[k][1] / 1024.0])
		print("[puente] censo: %s · lotes sin comprimir %.1f KB · mandado %.1f KB · tirados por atasco %d" % [
			" · ".join(PackedStringArray(partes)), _censo_crudo / 1024.0, b[0] / 1024.0, _censo_tirados])
		censo.clear()
		_censo_crudo = 0
	return b


static func _a_ws(url: String) -> String:
	var u := url.strip_edges().trim_suffix("/")
	if u.begins_with("https://"):
		return "wss://" + u.substr(8)
	if u.begins_with("http://"):
		return "ws://" + u.substr(7)
	return u


func _abrir_ws() -> Error:
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = 1 << 20
	_ws.inbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 8192
	_ws_listo = false
	motivo_cierre = ""
	var e := _ws.connect_to_url(_ws_url)
	if e != OK:
		_ws = null
		if not _anfitrion:
			_estado = CONNECTION_DISCONNECTED
		motivo_cierre = "no se pudo abrir la conexión (%d)" % e
	return e


# ----------------------------------------------------------------------------------------------- MultiplayerPeer
func _get_unique_id() -> int:
	return _mi_id


func _is_server() -> bool:
	return _anfitrion


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return _estado


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_target_peer(p: int) -> void:
	_target = p


func _get_transfer_channel() -> int:
	return _canal


func _set_transfer_channel(c: int) -> void:
	_canal = c


func _get_transfer_mode() -> TransferMode:
	return _modo


func _set_transfer_mode(m: TransferMode) -> void:
	_modo = m


func _set_refuse_new_connections(r: bool) -> void:
	_rechazar = r
	if _enet != null:
		_enet.refuse_new_connections = r


func _is_refusing_new_connections() -> bool:
	return _rechazar


func _get_available_packet_count() -> int:
	return _entrada.size()


func _get_packet_peer() -> int:
	return int(_entrada[0][0]) if not _entrada.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_entrada[0][1]) if not _entrada.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return int(_entrada[0][2]) if not _entrada.is_empty() else TRANSFER_MODE_RELIABLE


func _get_packet_script() -> PackedByteArray:
	if _entrada.is_empty():
		return PackedByteArray()
	return _entrada.pop_front()[3]


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if not _anfitrion:
		_al_lote(1, p_buffer)                  # el invitado solo habla con el anfitrion (el reparte a los demas)
		return OK
	var t := _target
	if t > 0:
		if _del_puente.has(t):
			_al_lote(t, p_buffer)
		else:
			_por_enet(t, p_buffer)
		return OK
	# a todos (0) o a todos menos uno (-id): por los dos caminos
	var fuera := -t
	if _enet != null:
		_por_enet(-fuera if fuera != 0 and not _del_puente.has(fuera) else 0, p_buffer)
	if not _del_puente.is_empty():
		_al_lote(-fuera if fuera != 0 and _del_puente.has(fuera) else 0, p_buffer)
	return OK


func _por_enet(t: int, buf: PackedByteArray) -> void:
	if _enet == null or _enet.get_connection_status() != CONNECTION_CONNECTED:
		return
	_enet.transfer_mode = _modo
	_enet.transfer_channel = _canal
	_enet.set_target_peer(t)
	_enet.put_packet(buf)


func _disconnect_peer(p: int, forzar: bool) -> void:
	if _del_puente.has(p):
		var m := PackedByteArray([T_ECHAR, 0, 0, 0, 0])
		m.encode_s32(1, p)
		_mandar(m)
		_del_puente.erase(p)
		peer_disconnected.emit(p)
	elif _enet != null:
		_enet.disconnect_peer(p, forzar)


func _close() -> void:
	_vaciar_lote()
	if _ws != null:
		_ws.close(1000, "adios")
		_ws.poll()
	_ws = null
	if _enet != null:
		_enet.close()
	_del_puente.clear()
	_estado = CONNECTION_DISCONNECTED


# ----------------------------------------------------------------------------------------------- envio
func _al_lote(dest: int, buf: PackedByteArray) -> void:
	if _ws == null:
		return
	# RED ATASCADA: lo no fiable se tira (llegara otro enseguida); lo fiable espera su turno
	if _modo != TRANSFER_MODE_RELIABLE and _ws.get_current_outbound_buffered_amount() > ATASCO:
		_censo_tirados += 1
		return
	var k := int(_modo)
	if not censo.has(k):
		censo[k] = [0, 0]
	censo[k][0] += 1
	censo[k][1] += buf.size()
	if _lote_hay and dest != _lote_dest:
		_vaciar_lote()                     # mismo orden que se pidio: un lote por destino seguido
	_lote_dest = dest
	_lote_hay = true
	_varint(_lote, buf.size())
	_lote.append((_canal << 2) | int(_modo))
	_lote.append_array(buf)


func _vaciar_lote() -> void:
	if not _lote_hay:
		return
	_lote_hay = false
	var cuerpo := _lote
	_lote = PackedByteArray()
	_censo_crudo += cuerpo.size()
	var cab := PackedByteArray()
	cab.append(T_DATOS)
	if _anfitrion:
		cab.resize(5)
		cab.encode_s32(1, _lote_dest)
	var comp := PackedByteArray()
	if cuerpo.size() >= COMPRIMIR_DESDE:
		comp = cuerpo.compress(FileAccess.COMPRESSION_ZSTD)
	if not comp.is_empty() and comp.size() + 4 < cuerpo.size():
		var n := cab.size()
		cab.resize(n + 5)
		cab[n] = 1
		cab.encode_u32(n + 1, cuerpo.size())
		cab.append_array(comp)
	else:
		cab.append(0)
		cab.append_array(cuerpo)
	_mandar(cab)


func _mandar(m: PackedByteArray) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send(m, WebSocketPeer.WRITE_MODE_BINARY)
	_bytes[0] += m.size()


static func _varint(a: PackedByteArray, n: int) -> void:
	while n >= 0x80:
		a.append((n & 0x7f) | 0x80)
		n >>= 7
	a.append(n)


# ----------------------------------------------------------------------------------------------- recepcion
func _poll() -> void:
	if _enet != null:
		_enet.poll()
		while _enet.get_available_packet_count() > 0:
			var de := _enet.get_packet_peer()
			var ca := _enet.get_packet_channel()
			var mo := _enet.get_packet_mode()
			_entrada.append([de, ca, mo, _enet.get_packet()])
	if _ws == null:
		return
	_vaciar_lote()
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_ws_listo = true
		while _ws.get_available_packet_count() > 0:
			var m := _ws.get_packet()
			_bytes[1] += m.size()
			_al_mensaje(m)
		if _anfitrion:
			_solo_t = 0.0 if not _del_puente.is_empty() else _solo_t + Engine.get_main_loop().root.get_process_delta_time()
			if _solo_t > ANFITRION_SOLO_S:
				print("[puente] anfitrion: nadie por el puente en %d s, lo cierro" % int(ANFITRION_SOLO_S))
				_ws.close(1000, "sin nadie")
	elif st == WebSocketPeer.STATE_CLOSED:
		var codigo := _ws.get_close_code()
		motivo_cierre = _motivo(codigo, _ws.get_close_reason())
		print("[puente] cerrado (%d) %s" % [codigo, motivo_cierre])
		_ws = null
		if _anfitrion:
			for id in _del_puente.keys():
				peer_disconnected.emit(int(id))
			_del_puente.clear()
		else:
			if _estado == CONNECTION_CONNECTED:
				peer_disconnected.emit(1)
			_estado = CONNECTION_DISCONNECTED


func _motivo(codigo: int, razon: String) -> String:
	match codigo:
		4001:
			return "el puente no tiene cupo este mes"
		4004:
			return "el anfitrión no contesta"
		4005:
			return "la sala está llena"
		4006:
			return "el anfitrión se ha ido"
		4008:
			return "el anfitrión te ha echado"
	if not _ws_listo:
		return "no se pudo conectar con el puente" + ("" if razon == "" else " (%s)" % razon)
	return razon


func _al_mensaje(m: PackedByteArray) -> void:
	if m.is_empty():
		return
	var t := m[0]
	if t == T_DATOS:
		var de := 1
		var pos := 1
		if _anfitrion:
			if m.size() < 6:
				return
			de = m.decode_s32(1)
			pos = 5
			if not _del_puente.has(de):
				return
		_leer_lote(de, m, pos)
	elif t == T_HOLA and not _anfitrion and m.size() >= 5:
		_mi_id = m.decode_s32(1)
		_estado = CONNECTION_CONNECTED
		print("[puente] dentro por el puente: soy el %d" % _mi_id)
		peer_connected.emit(1)
	elif t == T_ENTRA and _anfitrion and m.size() >= 5:
		var id := m.decode_s32(1)
		if _rechazar:
			_disconnect_peer(id, true)
			return
		_del_puente[id] = true
		print("[puente] entra el %d por el puente" % id)
		peer_connected.emit(id)
	elif t == T_SALE and _anfitrion and m.size() >= 5:
		var id := m.decode_s32(1)
		if _del_puente.erase(id):
			print("[puente] se va el %d del puente" % id)
			peer_disconnected.emit(id)


func _leer_lote(de: int, m: PackedByteArray, pos: int) -> void:
	if pos >= m.size():
		return
	var cuerpo: PackedByteArray
	if m[pos] & 1:
		var n := m.decode_u32(pos + 1)
		if n > (1 << 24):
			return
		cuerpo = m.slice(pos + 5).decompress(n, FileAccess.COMPRESSION_ZSTD)
	else:
		cuerpo = m.slice(pos + 1)
	var i := 0
	var tam := cuerpo.size()
	while i < tam:
		var largo := 0
		var corre := 0
		while i < tam:
			var b := cuerpo[i]
			i += 1
			largo |= (b & 0x7f) << corre
			corre += 7
			if b < 0x80:
				break
		if i >= tam:
			return
		var cm := cuerpo[i]
		i += 1
		if i + largo > tam:
			return
		_entrada.append([de, cm >> 2, cm & 3, cuerpo.slice(i, i + largo)])
		i += largo
