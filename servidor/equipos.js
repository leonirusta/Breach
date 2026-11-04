'use strict';
/**
 * EL EQUIPO (2026-09-30, pedido con captura de Pixel Gun: "FORMAR EQUIPO"). Al apretar EQUIPO en el lobby sale la
 * lista de tus amigos conectados; les mandas una invitacion, les sale arriba en el lobby con una cuenta atras (ACEPTAR /
 * RECHAZAR) y, al aceptar, entran en tu equipo: os veis juntos en el lobby y, cuando el LIDER pulsa ¡A LA BATALLA!,
 * todo el equipo entra en la MISMA sala y en el mismo bando.
 *
 * TODO VIVE EN MEMORIA, como las salas, la presencia y los avisos de amistad (index.js): un equipo dura lo que dura una
 * sesion de juego y cambia cada pocos segundos; escribirlo en el almacen se comeria la cuota de escrituras. Si la
 * instancia se duerme, los equipos se pierden y cada uno vuelve a estar solo (se ve al siguiente sondeo).
 *
 * El juego pregunta por /grupo/estado cada pocos segundos EN EL LOBBY (basta con el token: no se lee la cuenta) y el
 * latido de siempre (/latido, cada minuto en partida) mantiene vivo al que esta jugando. Sin noticias de alguien en
 * MIEMBRO_VIVO_MS (cerro el juego), sale del equipo solo.
 *
 * Rutas (todas POST, con la sesion del jugador):
 *   /grupo/estado     {donde, yo:{skin, arma, pintura, modo, mapa}} -> {grupo, invitaciones, enviadas, avisos}
 *   /grupo/invitar    {id: ID de 6 cifras de un amigo, max}          (solo el lider, o quien aun no tiene equipo)
 *   /grupo/responder  {id: invitacion, aceptar}
 *   /grupo/salir      {}
 *   /grupo/expulsar   {k: clave del miembro}                          (solo el lider)
 *   /grupo/sala       {sala, mapa, modo, anfitrion, lan, puerto}      (solo el lider: "he montado sala, venid")
 *
 * Hacia fuera NUNCA sale el `usuario` (es con lo que se entra en la cuenta): cada miembro va con una clave `k` que solo
 * vale dentro de su equipo, su ID publico de 6 cifras, su nombre, su nivel y su aspecto.
 */
const crypto = require('crypto');

const INVITACION_MS = 20000;       // la cuenta atras del aviso (ACEPTAR / RECHAZAR)
const MIEMBRO_VIVO_MS = 150000;    // como la presencia: el latido en partida es de 60 s
const SALA_VIVA_MS = 180000;       // la sala que monto el lider vale 3 minutos para entrar
const GRUPO_MAX = 5;               // el mas grande de los modos (bomba y duelo: 5 por bando)
const AVISOS_MAX = 8;
const AVISO_VIVO_MS = 300000;      // un aviso sin recoger en 5 minutos ya no dice nada (de un equipo de otro dia)
const TOPE = 20000;                // tope de entradas de cada mapa (como la presencia: se vacia si se pasa)

module.exports = function montarEquipos(ctx) {
  const {
    leerToken, cuentaDeToken, cuentaAjena, usuarioDeBusqueda, nivelDe, presencia, PRESENCIA_VIVA_MS,
    apuntarPresencia, responder, leerCuerpo, demasiado,
  } = ctx;

  const grupos = new Map();        // id -> { id, lider, miembros: Map(usuario -> ficha), sala, modo, mapa, v }
  const grupoDe = new Map();       // usuario -> id de su grupo
  const invitaciones = new Map();  // usuario invitado -> [{ id, de, para_nombre, ficha, max, hasta }]
  const avisos = new Map();        // usuario -> [{ tipo, nombre }]
  let nSala = 0;
  let limpiado = 0;

  const hex = (n) => crypto.randomBytes(n).toString('hex');
  const texto = (t, tope) => String(t == null ? '' : t).replace(/[\u0000-\u001f]/g, '').trim().slice(0, tope);

  function avisar(usuario, a) {
    if (avisos.size > TOPE) avisos.clear();
    const l = (avisos.get(usuario) || []).slice(-(AVISOS_MAX - 1));
    a.t = Date.now();
    l.push(a);
    avisos.set(usuario, l);
  }

  function vivo(usuario) {
    const p = presencia.get(usuario);
    return !!p && Date.now() - p.t < PRESENCIA_VIVA_MS;
  }

  /** Lo que se enseña de un jugador del equipo, sacado de su cuenta (al invitar y al aceptar; despues lo pone el) */
  function fichaDe(d, usuario) {
    const eq = d.equipo || {};
    return {
      k: hex(4), id_pub: d.id_pub || null, nombre: d.nombre || usuario, nivel: nivelDe(d.exp),
      skin: Number.isInteger(eq.avatar_skin) ? eq.avatar_skin : 0,
      arma: texto((eq.loadout || {}).primary, 40), pintura: '', visto: Date.now(), entro: Date.now(),
    };
  }

  function grupoDel(usuario) {
    const id = grupoDe.get(usuario);
    return id ? grupos.get(id) || null : null;
  }

  function crear(lider, ficha) {
    if (grupos.size > TOPE) { grupos.clear(); grupoDe.clear(); }
    const g = { id: hex(6), lider, miembros: new Map(), sala: null, modo: '', mapa: '', v: 1, chat: [], chat_n: 0, voz: new Map() };
    g.miembros.set(lider, ficha);
    grupos.set(g.id, g);
    grupoDe.set(lider, g.id);
    return g;
  }

  /** Sacar a alguien del equipo. `motivo`: 'salio' (se fue o dejo de dar señales) o 'expulsado'. */
  function quitar(usuario, motivo) {
    const g = grupoDel(usuario);
    grupoDe.delete(usuario);
    if (!g) return;
    const f = g.miembros.get(usuario);
    g.miembros.delete(usuario);
    g.v++;
    const nombre = f ? f.nombre : '';
    for (const u of g.miembros.keys()) avisar(u, { tipo: motivo === 'expulsado' ? 'expulsado' : 'salio', nombre });
    // SOLO QUEDA UNO: ya no hay equipo
    if (g.miembros.size <= 1) {
      for (const u of g.miembros.keys()) grupoDe.delete(u);
      grupos.delete(g.id);
      return;
    }
    // SE FUE EL LIDER: manda el que mas tiempo lleva
    if (g.lider === usuario) {
      let sig = null;
      for (const [u, fi] of g.miembros) if (!sig || fi.entro < g.miembros.get(sig).entro) sig = u;
      g.lider = sig;
      g.sala = null;
      avisar(sig, { tipo: 'lider', nombre: '' });
    }
  }

  /** Las invitaciones caducadas (se le dice al que invito) y los que ya no dan señales. Como mucho una vez por segundo. */
  function limpiar() {
    const ahora = Date.now();
    if (ahora - limpiado < 1000) return;
    limpiado = ahora;
    for (const [u, lista] of invitaciones) {
      const quedan = lista.filter((i) => i.hasta > ahora);
      for (const i of lista) if (i.hasta <= ahora) avisar(i.de, { tipo: 'caducada', nombre: i.para_nombre });
      if (quedan.length) invitaciones.set(u, quedan); else invitaciones.delete(u);
    }
    for (const g of [...grupos.values()]) {
      for (const [u, f] of [...g.miembros]) {
        if (ahora - f.visto > MIEMBRO_VIVO_MS) quitar(u, 'salio');
      }
    }
  }

  function tomarAvisos(usuario) {
    const l = avisos.get(usuario) || [];
    avisos.delete(usuario);
    const ahora = Date.now();
    return l.filter((a) => ahora - a.t < AVISO_VIVO_MS).map((a) => ({ tipo: a.tipo, nombre: a.nombre }));
  }

  function publico(g, usuario, ip) {
    const ahora = Date.now();
    const miembros = [...g.miembros].sort((a, b) => (a[0] === g.lider ? -1 : b[0] === g.lider ? 1 : a[1].entro - b[1].entro))
      .map(([u, f]) => {
        const p = presencia.get(u);
        return {
          k: f.k, id: f.id_pub, nombre: f.nombre, nivel: f.nivel, skin: f.skin, arma: f.arma, pintura: f.pintura,
          lider: u === g.lider, yo: u === usuario,
          donde: p && ahora - p.t < PRESENCIA_VIVA_MS ? p.donde : 'desconectado',
        };
      });
    let sala = null;
    if (g.sala && ahora - g.sala.t < SALA_VIVA_MS) {
      const s = g.sala;
      sala = { id: s.id, mapa: s.mapa, modo: s.modo, anfitrion: s.anfitrion, lan: s.lan, puerto: s.puerto, n: s.n,
        edad: Math.floor((ahora - s.t) / 1000), misma_red: !!ip && ip === s.ip };
    }
    return { id: g.id, v: g.v, soy_lider: g.lider === usuario, modo: g.modo, mapa: g.mapa, max: GRUPO_MAX, miembros, sala };
  }

  function pendientes(usuario) {
    const ahora = Date.now();
    return (invitaciones.get(usuario) || []).filter((i) => i.hasta > ahora).map((i) => ({
      id: i.id, nombre: i.ficha.nombre, nivel: i.ficha.nivel, skin: i.ficha.skin, id_pub: i.ficha.id_pub,
      quedan: Math.max(0, (i.hasta - ahora) / 1000),
    }));
  }

  /** Las que YO he mandado y siguen sin contestar: el ID del amigo y lo que les queda */
  function enviadas(usuario) {
    const ahora = Date.now();
    const out = [];
    for (const lista of invitaciones.values()) {
      for (const i of lista) if (i.de === usuario && i.hasta > ahora) out.push({ id: i.para_id, quedan: (i.hasta - ahora) / 1000 });
    }
    return out;
  }

  function usuarioDelToken(req) {
    const cab = req.headers['authorization'] || '';
    return leerToken(cab.startsWith('Bearer ') ? cab.slice(7) : '');
  }

  /** Lo que se ve desde index.js (/latido): mantiene vivo al que esta en partida y le dice si algo cambio */
  function latido(usuario) {
    const g = grupoDel(usuario);
    if (g) {
      const f = g.miembros.get(usuario);
      if (f) f.visto = Date.now();
    }
    const inv = (invitaciones.get(usuario) || []).length;
    if (!g && !inv && !avisos.has(usuario)) return {};
    return { grupo_v: (g ? g.id + ':' + g.v : '') + '|' + inv + '|' + (avisos.get(usuario) || []).length };
  }

  async function rutas(req, res, ruta, ip) {
    limpiar();
    // ---------------------------------------------------------------- el sondeo del lobby (sin leer la cuenta)
    if (ruta === '/grupo/estado') {
      const usuario = usuarioDelToken(req);
      if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      apuntarPresencia(usuario, b.donde);
      const g = grupoDel(usuario);
      if (g) {
        const f = g.miembros.get(usuario);
        if (f) {
          f.visto = Date.now();
          // SU ASPECTO LO DICE EL: es solo lo que se dibuja en el lobby de los demas (skin, arma, pintura)
          const yo = b.yo && typeof b.yo === 'object' ? b.yo : {};
          if (Number.isInteger(yo.skin) && yo.skin >= 0 && yo.skin < 200) f.skin = yo.skin;
          if (typeof yo.arma === 'string') f.arma = texto(yo.arma, 40);
          if (typeof yo.pintura === 'string') f.pintura = texto(yo.pintura, 60);
          if (g.lider === usuario) {
            if (typeof yo.modo === 'string' && texto(yo.modo, 20) !== g.modo) { g.modo = texto(yo.modo, 20); g.v++; }
            if (typeof yo.mapa === 'string' && texto(yo.mapa, 40) !== g.mapa) { g.mapa = texto(yo.mapa, 40); g.v++; }
          }
        }
      }
      // EL CHAT DEL EQUIPO (2026-10-15): los mensajes posteriores al ultimo que tiene el que pregunta
      let chat = [];
      if (g && Array.isArray(g.chat)) {
        const desde = Number.isFinite(Number(b.chat_desde)) ? Number(b.chat_desde) : g.chat_n;
        chat = g.chat.filter((m) => m.n > desde).slice(-20);
      }
      return responder(res, 200, {
        grupo: g ? publico(g, usuario, ip) : null, invitaciones: pendientes(usuario), enviadas: enviadas(usuario),
        avisos: tomarAvisos(usuario), max: GRUPO_MAX, chat, chat_n: g ? g.chat_n : 0,
      });
    }

    // ---------------------------------------------------------------- EL CHAT Y LA VOZ DEL EQUIPO EN EL LOBBY
    // (2026-10-15, pedido: "en el lobby, con mi equipo, chatear y hablar por microfono"). Todo en memoria.
    // Chat: se apunta en el grupo (los ultimos 40) y llega con /grupo/estado. Voz: cada uno manda sus paquetes de Opus
    // (base64) de medio segundo en medio segundo y se lleva los que le han dejado los demas (una cola por persona).
    if (ruta === '/grupo/chat') {
      const usuario = usuarioDelToken(req);
      if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('grupo-chat:' + usuario, 20, 10000)) return responder(res, 429, { error: 'espera un momento' });
      const b = await leerCuerpo(req);
      const g = grupoDel(usuario);
      const f = g && g.miembros.get(usuario);
      const txt = texto(b.txt, 120);
      if (!g || !f || !txt) return responder(res, 400, { error: 'sin equipo' });
      g.chat_n += 1;
      g.chat.push({ n: g.chat_n, k: f.k, nombre: f.nombre, txt });
      if (g.chat.length > 40) g.chat.splice(0, g.chat.length - 40);
      return responder(res, 200, { ok: true, chat_n: g.chat_n });
    }
    if (ruta === '/grupo/voz') {
      const usuario = usuarioDelToken(req);
      if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('grupo-voz:' + usuario, 60, 10000)) return responder(res, 429, { error: 'espera un momento' });
      const b = await leerCuerpo(req);
      const g = grupoDel(usuario);
      const f = g && g.miembros.get(usuario);
      if (!g || !f) return responder(res, 200, { voz: [] });
      if (!(g.voz instanceof Map)) g.voz = new Map();
      const mios = Array.isArray(b.p) ? b.p.filter((x) => typeof x === 'string' && x.length <= 2000).slice(0, 60) : [];
      if (mios.length) {
        for (const u of g.miembros.keys()) {
          if (u === usuario) continue;
          const cola = g.voz.get(u) || [];
          cola.push({ k: f.k, nombre: f.nombre, p: mios });
          while (cola.length > 20) cola.shift();         // si no lee (se fue), no se acumula
          g.voz.set(u, cola);
        }
      }
      const para_mi = g.voz.get(usuario) || [];
      g.voz.set(usuario, []);
      return responder(res, 200, { voz: para_mi });
    }

    // ---------------------------------------------------------------- invitar a un amigo
    if (ruta === '/grupo/invitar') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('grupo-inv:' + c.usuario, 30, 60000)) return responder(res, 429, { error: 'espera un momento' });
      const b = await leerCuerpo(req);
      const otro = await usuarioDeBusqueda(String(b.id || ''));
      if (!otro) return responder(res, 404, { error: 'ese jugador no existe' });
      if (otro === c.usuario) return responder(res, 400, { error: 'no puedes invitarte a ti mismo' });
      if (!(c.datos.amigos || []).includes(otro)) return responder(res, 400, { error: 'solo puedes invitar a tus amigos' });
      if (!vivo(otro)) return responder(res, 400, { error: 'no está conectado' });
      if (presencia.get(otro).donde === 'partida') return responder(res, 400, { error: 'está jugando: invítale cuando vuelva al lobby' });
      const g = grupoDel(c.usuario);
      if (g && g.lider !== c.usuario) return responder(res, 403, { error: 'solo el líder del equipo puede invitar' });
      if (g && g.miembros.has(otro)) return responder(res, 400, { error: 'ya está en tu equipo' });
      const max = Math.max(2, Math.min(GRUPO_MAX, parseInt(b.max, 10) || GRUPO_MAX));
      if (g && g.miembros.size >= max) return responder(res, 400, { error: `tu equipo ya está completo (${max})` });
      const ahora = Date.now();
      const lista = (invitaciones.get(otro) || []).filter((i) => i.hasta > ahora);
      if (lista.some((i) => i.de === c.usuario)) return responder(res, 400, { error: 'ya le has invitado: espera su respuesta' });
      const a = await cuentaAjena(otro);
      if (invitaciones.size > TOPE) invitaciones.clear();
      const inv = { id: hex(4), de: c.usuario, para_nombre: (a && a.nombre) || '', para_id: (a && a.id_pub) || null,
        ficha: fichaDe(c.datos, c.usuario), max, hasta: ahora + INVITACION_MS };
      lista.push(inv);
      invitaciones.set(otro, lista.slice(-5));
      return responder(res, 200, { ok: true, invitacion: { id: inv.id, quedan: INVITACION_MS / 1000 } });
    }

    // ---------------------------------------------------------------- aceptar o rechazar
    if (ruta === '/grupo/responder') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const lista = invitaciones.get(c.usuario) || [];
      const inv = lista.find((i) => i.id === String(b.id || ''));
      if (!inv) return responder(res, 404, { error: 'esa invitación ya no está' });
      invitaciones.set(c.usuario, lista.filter((i) => i !== inv));
      const nombre = c.datos.nombre || c.usuario;
      if (inv.hasta <= Date.now()) {
        avisar(inv.de, { tipo: 'caducada', nombre });
        return responder(res, 410, { error: 'la invitación ha caducado' });
      }
      if (b.aceptar !== true) {
        avisar(inv.de, { tipo: 'rechazada', nombre });
        return responder(res, 200, { ok: true });
      }
      let g = grupoDel(inv.de);
      if (g && g.miembros.has(c.usuario)) return responder(res, 200, { ok: true, grupo: publico(g, c.usuario, ip) });
      if (!g) {
        if (!vivo(inv.de)) return responder(res, 410, { error: 'quien te invitó ya no está conectado' });
        inv.ficha.visto = Date.now();
        g = crear(inv.de, inv.ficha);
      }
      if (g.miembros.size >= Math.min(GRUPO_MAX, inv.max)) return responder(res, 409, { error: 'ese equipo ya está completo' });
      // ESTABA EN OTRO EQUIPO: se va de aquel (y a los de alli se les dice)
      if (grupoDe.has(c.usuario)) quitar(c.usuario, 'salio');
      for (const u of g.miembros.keys()) avisar(u, { tipo: u === inv.de ? 'aceptada' : 'entro', nombre });
      g.miembros.set(c.usuario, fichaDe(c.datos, c.usuario));
      grupoDe.set(c.usuario, g.id);
      g.v++;
      return responder(res, 200, { ok: true, grupo: publico(g, c.usuario, ip) });
    }

    const usuario = usuarioDelToken(req);
    if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
    const g = grupoDel(usuario);

    // ---------------------------------------------------------------- salir
    if (ruta === '/grupo/salir') {
      quitar(usuario, 'salio');
      return responder(res, 200, { ok: true });
    }

    // ---------------------------------------------------------------- expulsar (el lider)
    if (ruta === '/grupo/expulsar') {
      const b = await leerCuerpo(req);
      if (!g) return responder(res, 400, { error: 'no estás en ningún equipo' });
      if (g.lider !== usuario) return responder(res, 403, { error: 'solo el líder puede expulsar' });
      let quien = null;
      for (const [u, f] of g.miembros) if (f.k === String(b.k || '') && u !== usuario) quien = u;
      if (!quien) return responder(res, 404, { error: 'ese jugador ya no está en el equipo' });
      avisar(quien, { tipo: 'te_expulsaron', nombre: g.miembros.get(usuario).nombre });
      quitar(quien, 'expulsado');
      return responder(res, 200, { ok: true });
    }

    // ---------------------------------------------------------------- la sala del lider: "venid"
    if (ruta === '/grupo/sala') {
      const b = await leerCuerpo(req);
      if (!g) return responder(res, 400, { error: 'no estás en ningún equipo' });
      if (g.lider !== usuario) return responder(res, 403, { error: 'solo el líder empieza la partida' });
      if (!b.sala && !b.lan) {
        if (g.sala) { g.sala = null; g.v++; }
        return responder(res, 200, { ok: true });
      }
      const lan = (Array.isArray(b.lan) ? b.lan : []).map((x) => texto(x, 45)).filter((x) => /^[0-9a-fA-F.:]+$/.test(x)).slice(0, 4);
      const puerto = parseInt(b.puerto, 10);
      g.sala = { id: texto(b.sala, 40), mapa: texto(b.mapa, 40), modo: texto(b.modo, 20), anfitrion: texto(b.anfitrion, 32),
        lan, puerto: puerto > 0 && puerto < 65536 ? puerto : 0, n: ++nSala, t: Date.now(), ip };
      g.v++;
      return responder(res, 200, { ok: true, n: g.sala.n });
    }

    return responder(res, 404, { error: 'no existe' });
  }

  return { rutas, latido };
};
