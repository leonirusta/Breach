'use strict';
/**
 * EL PUENTE (2026-10-01, pedido: "que se pueda jugar online con datos moviles o en la facultad, sin salir nunca del plan
 * gratis").
 *
 * La partida va directa por UDP entre el anfitrion y cada invitado (ENet; el agujero y el UPnP de salas_online.gd). Con
 * datos moviles o en redes que lo bloquean, ese camino no se abre. Entonces los dos se conectan AQUI por WebSocket (que
 * Cloud Run si admite: es HTTP) y este servidor reenvia los paquetes de uno a otro SIN MIRARLOS. La partida no cambia:
 * cada movil hace su fisica y su destruccion (el nucleo es determinista) y lo que viaja son las mismas ordenes de
 * siempre (disparos, daño al mundo, posiciones...), agrupadas por fotograma y comprimidas en el juego (puente_peer.gd).
 *
 * POR QUE AQUI Y NO EN OTRO SERVICIO: el servicio va con --max-instances=1, asi que el anfitrion y sus invitados caen
 * siempre en la misma maquina (con dos, cada uno podria acabar en una distinta y no se encontrarian).
 *
 * EL DINERO. Cloud Run cobra la instancia mientras haya una conexion abierta (180.000 vCPU-s gratis al mes = 50 h con
 * 1 vCPU) y los datos que SALEN (1 GiB gratis al mes desde Norteamerica). Por eso:
 *   - el anfitrion solo se conecta cuando un invitado lo pide (salas.js le avisa en el latido: `puente: true`) y se va
 *     solo cuando no le queda nadie por el puente;
 *   - se lleva la cuenta del mes (segundos con alguna conexion abierta y bytes enviados) en `puente/uso-AAAA-MM.json`, y
 *     al pasar el TOPE no se abren puentes nuevos hasta el mes siguiente (los que ya van, terminan). Topes por variable
 *     de entorno: PUENTE_HORAS_MES (30) y PUENTE_MB_MES (600): por debajo de lo gratis, que el resto del servidor
 *     (cuentas, tienda, latidos) tambien gasta.
 *
 * EL PROTOCOLO (binario; enteros de 4 bytes little endian):
 *   GET /puente?rol=anfitrion&sala=<id>&k=<llave del anuncio>          el anfitrion de esa sala
 *   GET /puente?rol=invitado&sala=<id>&t=<token de la cuenta>          un invitado
 *   juego -> aqui   anfitrion  01 [destino i32][datos]   destino > 0: a ese; 0: a todos; < 0: a todos menos -destino
 *                              02 [id i32]               echar a ese invitado
 *                   invitado   01 [datos]                siempre al anfitrion
 *   aqui -> juego   anfitrion  01 [de i32][datos] · 03 [id i32] ha entrado · 04 [id i32] se ha ido
 *                   invitado   05 [mi id i32] bienvenida (ya esta el anfitrion) · 01 [datos]
 *   Cierre con codigo: 4001 sin cupo este mes · 4002 no autorizado · 4004 el anfitrion no contesta · 4005 sala llena ·
 *                      4006 se ha ido el anfitrion · 4007 demasiado rapido · 4008 echado
 */
const crypto = require('crypto');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const MENSAJE_MAX = 256 * 1024;          // un mensaje del juego (un fotograma de paquetes comprimidos) no llega ni cerca
const COLA_MAX = 2 * 1024 * 1024;        // lo que puede quedar por mandar a uno antes de darle por perdido
const ESPERA_ANFITRION_MS = 25000;       // el invitado espera a que el anfitrion se conecte (su latido es cada 3 s)
const POR_SALA_MAX = 12;                 // jugadores + espectadores de una sala
const SALAS_MAX = 200;
const LATIDO_MS = 30000;                 // ping para que nada en medio cierre la conexion por silencio
const GUARDAR_MS = 10 * 60000;           // la cuenta del mes, cada 10 min (escrituras del bucket: ~150 al mes como mucho)
const RITMO_MAX = 96 * 1024;             // bytes por segundo de un invitado hacia aqui (la partida va muy por debajo)

module.exports = function montarPuente(ctx) {
  const { leer, escribir, leerToken, salas } = ctx;
  const HORAS_MES = Math.max(1, Number(process.env.PUENTE_HORAS_MES) || 30);
  const MB_MES = Math.max(10, Number(process.env.PUENTE_MB_MES) || 600);

  // ------------------------------------------------------------------ la cuenta del mes
  const uso = { mes: '', bytes: 0, segundos: 0, partidas: 0, generacion: null, sucio: false, cargado: false };
  function mesActual() { return new Date().toISOString().slice(0, 7); }
  function objetoUso(m) { return `puente/uso-${m}.json`; }
  async function cargarUso() {
    const m = mesActual();
    if (uso.cargado && uso.mes === m) return;
    if (uso.mes && uso.mes !== m) await guardarUso();          // cambia el mes: se guarda el viejo y se empieza
    try {
      const e = await leer(objetoUso(m));
      Object.assign(uso, { mes: m, bytes: 0, segundos: 0, partidas: 0, generacion: e ? e.generacion : '0' },
        e && e.datos ? { bytes: +e.datos.bytes || 0, segundos: +e.datos.segundos || 0, partidas: +e.datos.partidas || 0 } : {});
      uso.cargado = true;
    } catch (err) {
      console.error('[puente] no pude leer la cuenta del mes', err.message);
    }
  }
  async function guardarUso() {
    if (!uso.cargado || !uso.sucio) return;
    try {
      const datos = { mes: uso.mes, bytes: uso.bytes, segundos: Math.round(uso.segundos), partidas: uso.partidas,
        horas: +(uso.segundos / 3600).toFixed(2), mb: +(uso.bytes / 1048576).toFixed(1), t: new Date().toISOString() };
      let gen = await escribir(objetoUso(uso.mes), datos, uso.generacion);
      if (gen === null) {             // otra escritura en medio (no deberia: una instancia). Se relee y se suma lo nuestro
        const e = await leer(objetoUso(uso.mes));
        gen = await escribir(objetoUso(uso.mes), datos, e ? e.generacion : '0');
      }
      if (gen !== null) { uso.generacion = gen; uso.sucio = false; }
    } catch (err) {
      console.error('[puente] no pude guardar la cuenta del mes', err.message);
    }
  }
  function sinCupo() {
    return uso.segundos >= HORAS_MES * 3600 * 0.95 || uso.bytes >= MB_MES * 1048576 * 0.95;
  }
  cargarUso();
  setInterval(() => { cargarUso().then(guardarUso); }, GUARDAR_MS).unref();
  process.once('SIGTERM', () => { guardarUso().finally(() => process.exit(0)); });

  // ------------------------------------------------------------------ las conexiones
  const puentes = new Map();      // sala -> {anfitrion, invitados: Map id->conexion, creado}
  let abiertas = 0;
  let desde = 0;                  // cuando paso de 0 a 1 conexion abierta (para contar el tiempo que se cobra)

  function contarTiempo() {
    if (abiertas > 0 && desde) {
      const ahora = Date.now();
      uso.segundos += (ahora - desde) / 1000;
      desde = ahora;
      uso.sucio = true;
    }
  }
  setInterval(contarTiempo, 15000).unref();

  function marco(op, cuerpo) {
    const n = cuerpo.length;
    let cab;
    if (n < 126) { cab = Buffer.alloc(2); cab[1] = n; }
    else if (n < 65536) { cab = Buffer.alloc(4); cab[1] = 126; cab.writeUInt16BE(n, 2); }
    else { cab = Buffer.alloc(10); cab[1] = 127; cab.writeBigUInt64BE(BigInt(n), 2); }
    cab[0] = 0x80 | op;
    return [cab, cuerpo];
  }

  function enviar(c, op, cuerpo) {
    if (c.cerrada) return;
    if (c.socket.writableLength > COLA_MAX) { cerrar(c, 4007, 'no da abasto'); return; }
    const [cab, cu] = marco(op, cuerpo);
    c.socket.write(cab);
    if (cu.length) c.socket.write(cu);
    uso.bytes += cab.length + cu.length;
    uso.sucio = true;
  }
  function binario(c, buf) { enviar(c, 0x2, buf); }
  function conId(tipo, id, resto) {
    const b = Buffer.allocUnsafe(5 + (resto ? resto.length : 0));
    b[0] = tipo;
    b.writeInt32LE(id, 1);
    if (resto) resto.copy(b, 5);
    return b;
  }

  function cerrar(c, codigo, motivo) {
    if (c.cerrada) return;
    c.cerrada = true;
    try {
      const m = Buffer.from(String(motivo || '').slice(0, 100), 'utf8');
      const cu = Buffer.alloc(2 + m.length);
      cu.writeUInt16BE(codigo || 1000, 0);
      m.copy(cu, 2);
      const [cab, x] = marco(0x8, cu);
      c.socket.write(cab);
      c.socket.end(x);
    } catch { /* ya estaba cerrada */ }
    setTimeout(() => c.socket.destroy(), 2000).unref();
    soltar(c);
  }

  function soltar(c) {
    if (c.soltada) return;
    c.soltada = true;
    contarTiempo();
    abiertas = Math.max(0, abiertas - 1);
    if (abiertas === 0) desde = 0;
    clearInterval(c.latido);
    clearTimeout(c.espera);
    const p = puentes.get(c.sala);
    if (!p) return;
    if (c.rol === 'anfitrion') {
      if (p.anfitrion === c) {
        p.anfitrion = null;
        for (const i of p.invitados.values()) cerrar(i, 4006, 'el anfitrion se ha ido');
        puentes.delete(c.sala);
      }
    } else if (p.invitados.get(c.id) === c) {
      p.invitados.delete(c.id);
      if (p.anfitrion && c.bienvenido) binario(p.anfitrion, conId(0x04, c.id));
      if (!p.anfitrion && p.invitados.size === 0) puentes.delete(c.sala);
    }
  }

  // un mensaje entero del juego
  function alMensaje(c, datos) {
    const p = puentes.get(c.sala);
    if (!p || datos.length < 1) return;
    const tipo = datos[0];
    if (c.rol === 'anfitrion') {
      if (datos.length < 5) return;
      const destino = datos.readInt32LE(1);
      if (tipo === 0x02) {
        const i = p.invitados.get(destino);
        if (i) cerrar(i, 4008, 'echado por el anfitrion');
        return;
      }
      if (tipo !== 0x01) return;
      // EL MISMO MENSAJE PARA TODOS: se arma una vez y se manda a cada uno (sin copiar los datos)
      const cuerpo = Buffer.concat([Buffer.from([0x01]), datos.subarray(5)]);
      if (destino > 0) {
        const i = p.invitados.get(destino);
        if (i && i.bienvenido) binario(i, cuerpo);
      } else {
        for (const [id, i] of p.invitados) if (i.bienvenido && id !== -destino) binario(i, cuerpo);
      }
    } else {
      if (tipo !== 0x01 || !c.bienvenido || !p.anfitrion) return;
      // freno: un invitado no puede inundar (la partida manda unos pocos KB/s)
      const ahora = Date.now();
      if (ahora - c.ritmoT > 1000) { c.ritmoT = ahora; c.ritmoN = 0; }
      c.ritmoN += datos.length;
      if (c.ritmoN > RITMO_MAX) return;     // se tira: lo fiable lo vuelve a pedir el juego (reconciliacion)
      const b = Buffer.allocUnsafe(datos.length + 4);
      b[0] = 0x01;
      b.writeInt32LE(c.id, 1);
      datos.copy(b, 5, 1);
      binario(p.anfitrion, b);
    }
  }

  // ------------------------------------------------------------------ lectura de marcos (RFC 6455)
  function alDatos(c, trozo) {
    c.buf = c.buf.length ? Buffer.concat([c.buf, trozo]) : trozo;
    for (;;) {
      const b = c.buf;
      if (b.length < 2) return;
      const fin = (b[0] & 0x80) !== 0;
      const op = b[0] & 0x0f;
      const enmascarado = (b[1] & 0x80) !== 0;
      let n = b[1] & 0x7f;
      let pos = 2;
      if (n === 126) { if (b.length < 4) return; n = b.readUInt16BE(2); pos = 4; }
      else if (n === 127) {
        if (b.length < 10) return;
        const g = b.readBigUInt64BE(2);
        if (g > BigInt(MENSAJE_MAX)) return cerrar(c, 1009, 'demasiado grande');
        n = Number(g); pos = 10;
      }
      if (!enmascarado) return cerrar(c, 1002, 'sin mascara');
      if (n > MENSAJE_MAX) return cerrar(c, 1009, 'demasiado grande');
      if (b.length < pos + 4 + n) return;
      const masc = b.subarray(pos, pos + 4);
      const cuerpo = Buffer.from(b.subarray(pos + 4, pos + 4 + n));
      for (let i = 0; i < n; i++) cuerpo[i] ^= masc[i & 3];
      c.buf = b.subarray(pos + 4 + n);
      if (op === 0x8) return cerrar(c, 1000, '');
      if (op === 0x9) { enviar(c, 0xA, cuerpo); continue; }
      if (op === 0xA) continue;
      if (op === 0x2 || op === 0x0) {
        c.trozos.push(cuerpo);
        c.trozosN += cuerpo.length;
        if (c.trozosN > MENSAJE_MAX) return cerrar(c, 1009, 'demasiado grande');
        if (fin) {
          const m = c.trozos.length === 1 ? c.trozos[0] : Buffer.concat(c.trozos);
          c.trozos = [];
          c.trozosN = 0;
          alMensaje(c, m);
        }
        continue;
      }
      return cerrar(c, 1003, 'solo binario');
    }
  }

  function rechazar(socket, codigo, texto) {
    try {
      socket.end(`HTTP/1.1 ${codigo} ${texto}\r\nContent-Type: text/plain\r\nContent-Length: ${Buffer.byteLength(texto)}\r\n` +
        `Connection: close\r\n\r\n${texto}`);
    } catch { /* nada */ }
  }

  function bienvenida(p, i) {
    if (i.bienvenido || !p.anfitrion) return;
    i.bienvenido = true;
    clearTimeout(i.espera);
    binario(i, conId(0x05, i.id));
    binario(p.anfitrion, conId(0x03, i.id));
  }

  // ------------------------------------------------------------------ la entrada (el 'upgrade' de http)
  async function upgrade(req, socket, cabeza) {
    const url = new URL(req.url, 'http://x');
    if (url.pathname !== '/puente') return rechazar(socket, 404, 'no existe');
    const clave = req.headers['sec-websocket-key'];
    if (!clave || String(req.headers['upgrade'] || '').toLowerCase() !== 'websocket') return rechazar(socket, 400, 'no es websocket');
    await cargarUso();
    const rol = url.searchParams.get('rol') === 'anfitrion' ? 'anfitrion' : 'invitado';
    const salaId = String(url.searchParams.get('sala') || '').slice(0, 40);
    const sala = salas.get(salaId);
    if (!sala) return rechazar(socket, 404, 'esa sala ya no existe');
    let usuario = '';
    if (rol === 'anfitrion') {
      if (sala.llave !== String(url.searchParams.get('k') || '')) return rechazar(socket, 403, 'no autorizado');
    } else {
      usuario = leerToken(String(url.searchParams.get('t') || ''));
      if (!usuario) return rechazar(socket, 403, 'hace falta iniciar sesion');
    }
    let p = puentes.get(salaId);
    // SIN CUPO: no se abre un puente NUEVO (uno que ya va, con su anfitrion dentro, puede recibir a uno mas)
    if (sinCupo() && !(p && p.anfitrion)) return rechazar(socket, 503, 'el puente no tiene cupo este mes');
    if (!p) {
      if (puentes.size >= SALAS_MAX) return rechazar(socket, 503, 'puente lleno');
      p = { anfitrion: null, invitados: new Map(), creado: Date.now() };
      puentes.set(salaId, p);
    }
    if (rol === 'invitado' && p.invitados.size >= POR_SALA_MAX) return rechazar(socket, 503, 'sala llena');

    const acepta = crypto.createHash('sha1').update(clave + GUID).digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${acepta}\r\n\r\n`);
    socket.setNoDelay(true);
    const c = { socket, rol, sala: salaId, usuario, id: 0, buf: Buffer.alloc(0), trozos: [], trozosN: 0, cerrada: false,
      soltada: false, bienvenido: false, ritmoT: 0, ritmoN: 0, latido: null, espera: null };
    abiertas++;
    if (abiertas === 1) desde = Date.now();
    socket.on('data', (d) => alDatos(c, d));
    socket.on('close', () => soltar(c));
    socket.on('error', () => soltar(c));
    c.latido = setInterval(() => enviar(c, 0x9, Buffer.alloc(0)), LATIDO_MS);
    if (cabeza && cabeza.length) alDatos(c, cabeza);

    if (rol === 'anfitrion') {
      if (p.anfitrion) cerrar(p.anfitrion, 4006, 'otra conexion del anfitrion');
      p.anfitrion = c;
      c.id = 1;
      uso.partidas++;
      uso.sucio = true;
      console.log('[puente] anfitrion de', salaId, '·', p.invitados.size, 'esperando');
      for (const i of p.invitados.values()) bienvenida(p, i);
    } else {
      let id = 0;
      do { id = 2 + crypto.randomInt(0x7ffffff0); } while (p.invitados.has(id));
      c.id = id;
      p.invitados.set(id, c);
      console.log('[puente] invitado', id, 'a', salaId, p.anfitrion ? '(anfitrion dentro)' : '(esperando al anfitrion)');
      if (p.anfitrion) bienvenida(p, c);
      else c.espera = setTimeout(() => cerrar(c, 4004, 'el anfitrion no contesta'), ESPERA_ANFITRION_MS);
    }
  }

  /** ¿Hay alguien esperando en el puente de esta sala sin anfitrion? (va en la respuesta del latido de la sala) */
  function pide(salaId) {
    const p = puentes.get(salaId);
    return !!(p && !p.anfitrion && p.invitados.size > 0);
  }

  /** La sala se ha cerrado: fuera su puente */
  function cerrarSala(salaId) {
    const p = puentes.get(salaId);
    if (!p) return;
    if (p.anfitrion) cerrar(p.anfitrion, 4006, 'sala cerrada');
    for (const i of p.invitados.values()) cerrar(i, 4006, 'sala cerrada');
    puentes.delete(salaId);
  }

  function estado() {
    contarTiempo();
    return { mes: uso.mes, horas: +(uso.segundos / 3600).toFixed(2), horas_tope: HORAS_MES, mb: +(uso.bytes / 1048576).toFixed(1),
      mb_tope: MB_MES, partidas: uso.partidas, abiertas, puentes: puentes.size, sin_cupo: sinCupo() };
  }

  return { upgrade, pide, cerrarSala, estado };
};
