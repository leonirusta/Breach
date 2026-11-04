'use strict';
/**
 * EL PANEL DE ADMINISTRACION (2026-09-28, pedido: "un APK administrador, bien profesional, CRUD: editar los usuarios
 * registrados, su nombre y usuario, contraseñas si no se registraron por Google, su experiencia, nivel, oro y
 * diamantes, enviarles regalos...").
 *
 * Lo usa la app `admin/` (Godot, APK aparte). Todo va bajo /admin/ y pide un TOKEN DE ADMINISTRADOR, que se consigue
 * con la clave del panel:
 *
 *   BREACH_ADMIN_HASH   "scrypt:<sal>:<hash>" de la clave. La clave NO vive en ningun sitio: ni en el codigo, ni en
 *                       el APK, ni en las variables del servicio (solo su hash). La pone `configurar_admin.bat`.
 *                       Sin esta variable el panel no existe (503).
 *
 * El token de administrador se firma con OTRA llave que el de los jugadores (SECRETO + el hash de la clave): uno de
 * jugador no vale aqui, uno de aqui no vale como jugador, y cambiar la clave del panel echa a todas las sesiones
 * del panel. Dura 12 horas.
 *
 * "oro" es `monedas` (las de jugar) y "diamantes" son `creditos` (los de dinero real).
 *
 * LOS REGALOS. Uno a uno van en la cuenta (`regalos`); a todos, en `admin/regalos_todos.json` (en memoria, releido
 * cada 5 minutos: el servidor es UNA instancia). El juego los ve en el perfil (`regalos`), los enseña en la pantalla
 * de recompensa del lobby y los reclama con /regalo/reclamar: solo entonces se suman.
 */
const crypto = require('crypto');

const HORAS_ADMIN = 12;
const POR_PAGINA = 20;
const REGISTRO_MAX = 40;          // lo que se apunta en cada cuenta de lo que le hizo el panel
const REGALOS_MAX = 30;           // regalos pendientes por cuenta
const VISTOS_MAX = 300;           // regalos "a todos" ya reclamados que recuerda una cuenta
const TODOS_RELEER_MS = 300000;
const TOPE_NUMERO = 1000000000;
// cubos, carta (copias de una carta) y cofre (por abrir, de una rareza): 2026-10-02, pedido ("no puedo enviar cartas ni cubos")
const TIPOS_REGALO = ['monedas', 'creditos', 'exp', 'articulo', 'cubos', 'carta', 'cofre'];
const RAREZAS_COFRE = ['común', 'poco común', 'raro', 'épico', 'legendario', 'mítico'];
const USUARIO_OK = /^[a-z0-9_-]{3,16}$/;

module.exports = function montarAdmin(ctx) {
  const {
    SECRETO, leer, escribir, borrarObjeto, listar, aCache, borrarCache, cuentaAjena, actualizar,
    hashClave, igualesEnTiempoFijo, normalizarUsuario, normalizarNombre, claveNombre, claveValida, objetoDe,
    reservarNombre, soltarNombre, nivelDe, perfilPublico, PRECIOS, CATALOGO, presencia, PRESENCIA_VIVA_MS,
    salas, responder, leerCuerpo, demasiado, claveId, tienda, espectar, reportes, contacto, PROGRESO, darCarta,
  } = ctx;
  const CARTAS = (PROGRESO && PROGRESO.cofres && PROGRESO.cofres.cartas) || { ids: [], nombres: {} };
  const ADMIN_HASH = process.env.BREACH_ADMIN_HASH || '';
  const LLAVE = SECRETO + '|admin|' + ADMIN_HASH;

  // -------------------------------------------------------------------- la clave y el token del panel
  function claveCorrecta(clave) {
    const [tipo, sal, hash] = ADMIN_HASH.split(':');
    if (tipo !== 'scrypt' || !sal || !hash || typeof clave !== 'string' || clave.length < 8 || clave.length > 128) return false;
    return igualesEnTiempoFijo(hashClave(clave, sal), hash);
  }
  function firmarAdmin() {
    const cuerpo = Buffer.from(JSON.stringify({ adm: 1, c: Date.now() + HORAS_ADMIN * 3600000,
      n: crypto.randomBytes(6).toString('hex') })).toString('base64url');
    return cuerpo + '.' + crypto.createHmac('sha256', LLAVE).update('admin:' + cuerpo).digest('base64url');
  }
  function tokenAdminValido(req) {
    const cab = String(req.headers['authorization'] || '');
    const tok = cab.startsWith('Bearer ') ? cab.slice(7) : '';
    if (!tok.includes('.')) return false;
    const [cuerpo, firma] = tok.split('.');
    const esperada = crypto.createHmac('sha256', LLAVE).update('admin:' + cuerpo).digest('base64url');
    if (!igualesEnTiempoFijo(firma, esperada)) return false;
    try {
      const d = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
      return d.adm === 1 && Date.now() < d.c;
    } catch { return false; }
  }

  // -------------------------------------------------------------------- los regalos "a todos"
  let todos = { version: 0, lista: [] };
  let todosLeido = 0;
  async function cargarTodos(forzar) {
    if (!forzar && Date.now() - todosLeido < TODOS_RELEER_MS) return todos;
    todosLeido = Date.now();
    try {
      const e = await leer('admin/regalos_todos.json');
      if (e && e.datos && Array.isArray(e.datos.lista)) todos = { version: e.datos.version || 0, lista: e.datos.lista };
    } catch (err) { console.error('[admin] no se pudieron leer los regalos a todos', err.message); }
    return todos;
  }
  async function guardarTodos() {
    const ahora = Date.now();
    todos.lista = todos.lista.filter((g) => g.hasta > ahora);     // los caducados se van al guardar
    todos.version = (todos.version || 0) + 1;
    await escribir('admin/regalos_todos.json', todos, null);
    todosLeido = Date.now();
  }
  /** Lo que tiene esta cuenta por reclamar: lo suyo y lo de todos que no haya reclamado aun. */
  function regalosPendientes(cu) {
    const ahora = Date.now();
    const propios = (cu.regalos || []).map((g) => ({ ...g, todos: false }));
    const vistos = new Set(cu.regalos_vistos || []);
    const creada = Date.parse(cu.creada || '') || 0;
    const comunes = todos.lista.filter((g) => g.hasta > ahora && !vistos.has(g.id) && creada < g.hasta)
      .map((g) => ({ id: g.id, tipo: g.tipo, cantidad: g.cantidad, articulo: g.articulo, mensaje: g.mensaje, t: g.t, todos: true }));
    return propios.concat(comunes);
  }
  /** Lo que el juego ve de cada regalo */
  function regaloPublico(g) {
    return { id: g.id, tipo: g.tipo, cantidad: g.cantidad || 0, articulo: g.articulo || '', mensaje: g.mensaje || '',
      nombre: g.articulo ? nombreArticulo(g.articulo) : (g.carta ? nombreCarta(g.carta) : ''), carta: g.carta || '',
      rareza: g.rareza || 0, t: g.t, todos: !!g.todos };
  }
  function nombreCarta(id) {
    return (CARTAS.nombres && CARTAS.nombres[id]) || id;
  }
  /** El nombre que se ve: el que puso el panel en la tienda, o el del juego */
  function nombreArticulo(clave) {
    return tienda.nombreDe(clave);
  }
  /** Un articulo de la tienda tal como lo ve el panel: lo de ahora y lo de fabrica */
  function articuloTienda(k) {
    const aj = tienda.ajustes();
    return { clave: k, tipo: (CATALOGO[k] || {}).t || '', nombre: tienda.nombreDe(k),
      nombre_orig: (CATALOGO[k] && CATALOGO[k].n) || k, precio: tienda.precioDe(k), precio_orig: PRECIOS[k],
      cambiado: !!(aj.precios[k] || aj.nombres[k]) };
  }
  /** Valida un regalo que manda el panel. Devuelve {regalo} o {error}. */
  function regaloDe(b) {
    const tipo = String(b.tipo || '');
    if (!TIPOS_REGALO.includes(tipo)) return { error: 'tipo de regalo no valido' };
    const g = { id: crypto.randomBytes(6).toString('hex'), tipo, t: new Date().toISOString(),
      mensaje: limpio(b.mensaje, 120) };
    if (tipo === 'articulo') {
      const art = String(b.articulo || '').slice(0, 48);
      if (!Object.prototype.hasOwnProperty.call(PRECIOS, art)) return { error: 'ese articulo no existe en la tienda' };
      g.articulo = art;
    } else if (tipo === 'carta') {
      const id = String(b.carta || '');
      if (!CARTAS.ids.includes(id)) return { error: 'esa carta no existe' };
      const n = parseInt(b.cantidad, 10);
      if (!(n > 0 && n <= 1000)) return { error: 'las copias tienen que ser de 1 a 1.000' };
      g.carta = id;
      g.cantidad = n;
    } else if (tipo === 'cofre') {
      const r = parseInt(b.rareza, 10);
      if (!(r >= 0 && r <= 5)) return { error: 'la rareza del cofre tiene que ser de 0 a 5' };
      const n = parseInt(b.cantidad, 10);
      if (!(n > 0 && n <= 20)) return { error: 'de 1 a 20 cofres' };
      g.rareza = r;
      g.cantidad = n;
    } else {
      const n = parseInt(b.cantidad, 10);
      if (!(n > 0 && n <= 10000000)) return { error: 'la cantidad tiene que ser de 1 a 10.000.000' };
      g.cantidad = n;
    }
    return { regalo: g };
  }
  function aplicarRegalo(cu, g) {
    if (g.tipo === 'monedas') cu.monedas = (cu.monedas || 0) + g.cantidad;
    else if (g.tipo === 'creditos') cu.creditos = (cu.creditos || 0) + g.cantidad;
    else if (g.tipo === 'exp') cu.exp = (cu.exp || 0) + g.cantidad;
    else if (g.tipo === 'cubos') cu.cubos = (cu.cubos || 0) + g.cantidad;
    else if (g.tipo === 'carta') darCarta(cu, g.carta, g.cantidad);
    else if (g.tipo === 'cofre') {
      const nuevos = new Array(g.cantidad).fill(Math.max(0, Math.min(5, g.rareza || 0)));
      cu.cofres = (cu.cofres || []).concat(nuevos).slice(-50);
    }
    else if (g.tipo === 'articulo') {
      cu.armas = cu.armas || [];
      if (!cu.armas.includes(g.articulo)) cu.armas.push(g.articulo);
    }
  }
  function textoRegalo(g) {
    if (g.tipo === 'articulo') return nombreArticulo(g.articulo);
    if (g.tipo === 'carta') return `${g.cantidad} ${g.cantidad === 1 ? 'copia' : 'copias'} de la carta ${nombreCarta(g.carta)}`;
    if (g.tipo === 'cofre') return `${g.cantidad} ${g.cantidad === 1 ? 'cofre' : 'cofres'} ${RAREZAS_COFRE[g.rareza || 0] || ''}`;
    const que = { monedas: 'oro', creditos: 'diamantes', exp: 'EXP', cubos: 'cubos de fuerza' }[g.tipo] || g.tipo;
    return `${g.cantidad} de ${que}`;
  }

  // -------------------------------------------------------------------- los codigos
  function normalizarCodigo(c) {
    const t = String(c == null ? '' : c).trim().toUpperCase().replace(/\s+/g, '');
    return /^[A-Z0-9-]{4,24}$/.test(t) ? t : '';
  }
  function claveCodigo(c) { return 'codigos/' + c + '.json'; }
  function codigoPublico(d) {
    const caducado = !!d.hasta && Date.parse(d.hasta) < Date.now();
    const agotado = d.usos_max > 0 && (d.usados || []).length >= d.usos_max;
    return { codigo: d.codigo, modo: d.modo, usos_max: d.usos_max, usos: (d.usados || []).length, hasta: d.hasta,
      nota: d.nota || '', creado: d.creado, activo: !caducado && !agotado, caducado, agotado,
      items: (d.items || []).map((g) => ({ tipo: g.tipo, cantidad: g.cantidad || 0, articulo: g.articulo || '', carta: g.carta || '',
        rareza: g.rareza || 0, texto: textoRegalo(g) })),
      ultimos: (d.usados || []).slice(-10) };
  }

  // -------------------------------------------------------------------- utilidades
  function limpio(t, tope) {
    return String(t == null ? '' : t).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, tope);
  }
  function numero(v) {
    const n = Math.floor(Number(v));
    return Number.isFinite(n) ? Math.max(0, Math.min(TOPE_NUMERO, n)) : null;
  }
  function expDeNivel(n) { return Math.floor(n * (n - 1) / 2) * 1000; }
  function apuntar(cu, que) {
    cu.registro_admin = (cu.registro_admin || []).concat([{ t: new Date().toISOString(), que }]).slice(-REGISTRO_MAX);
  }
  function estadoPresencia(usuario) {
    const p = presencia.get(usuario);
    return p && Date.now() - p.t < PRESENCIA_VIVA_MS ? p.donde : 'desconectado';
  }
  /** Lo que ve el panel en la lista */
  function resumen(usuario, d) {
    return {
      usuario, nombre: d.nombre || '', nivel: nivelDe(d.exp), exp: d.exp || 0, monedas: d.monedas || 0,
      creditos: d.creditos || 0, google: !!d.google, bloqueada: !!d.bloqueada, id_pub: d.id_pub || null,
      ultima: d.ultima || d.creada || null, estado: estadoPresencia(usuario),
      regalos: regalosPendientes(d).length,
    };
  }
  /** Lo que ve el panel en la ficha: todo menos la sal y el hash de la clave */
  function ficha(usuario, d) {
    const n = nivelDe(d.exp);
    return {
      ...resumen(usuario, d),
      correo: d.correo || '', tiene_clave: !!d.hash, nombre_elegido: d.nombre_elegido === true,
      exp_nivel: expDeNivel(n), exp_siguiente: expDeNivel(n + 1),
      partidas: d.partidas || 0, ganadas: d.ganadas || 0, creada: d.creada || null,
      motivo_bloqueo: d.motivo_bloqueo || '',
      armas: (d.armas || []).map((k) => ({ clave: k, nombre: nombreArticulo(k), tipo: (CATALOGO[k] || {}).t || '' })),
      amigos: (d.amigos || []).length, pagos: (d.pagos || []).length,
      regalos_pendientes: regalosPendientes(d).map(regaloPublico),
      registro: (d.registro_admin || []).slice().reverse(),
      // los ME GUSTA recibidos y los REPORTES en contra (reportes.js; los de la memoria del servidor)
      likes: d.likes || 0, reportes: reportes ? reportes.contra(usuario) : null,
    };
  }

  // -------------------------------------------------------------------- la lista de cuentas (cache corta)
  let listaCache = { t: 0, cuentas: null, nombres: null };
  function olvidarLista() { listaCache = { t: 0, cuentas: null, nombres: null }; }
  async function todasLasCuentas() {
    if (listaCache.cuentas && Date.now() - listaCache.t < 20000) return listaCache;
    const cuentas = await listar('cuentas/');
    const nombres = await listar('nombres/');
    cuentas.sort((a, b) => b.t - a.t);
    listaCache = { t: Date.now(), cuentas, nombres };
    return listaCache;
  }
  function sinAcentos(s) {
    return String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, '_');
  }
  async function buscar(q) {
    const { cuentas, nombres } = await todasLasCuentas();
    const t = String(q || '').trim();
    if (!t) return cuentas.map((c) => c.nombre);
    if (/^\d{6}$/.test(t)) {
      const e = await leer(claveId(t));
      return e && e.datos && e.datos.usuario ? [e.datos.usuario] : [];
    }
    const s = sinAcentos(t);
    const orden = new Map(cuentas.map((c, i) => [c.nombre, i]));
    const out = new Set(cuentas.filter((c) => c.nombre.includes(s)).map((c) => c.nombre));
    // por el NOMBRE que se ve: la lista de reservas trae los nombres; cada coincidencia dice de quien es
    const porNombre = nombres.filter((n) => n.nombre.includes(s)).slice(0, 25);
    const dueños = await Promise.all(porNombre.map((n) => leer('nombres/' + n.nombre + '.json').catch(() => null)));
    for (const e of dueños) if (e && e.datos && e.datos.usuario) out.add(e.datos.usuario);
    return [...out].sort((a, b) => (orden.has(a) ? orden.get(a) : 1e9) - (orden.has(b) ? orden.get(b) : 1e9));
  }

  /** Quita `viejo` (o lo cambia por `nuevo`) de las listas de amigos de los demas. Lo mejor que se pueda. */
  async function arreglarAmigos(d, viejo, nuevo) {
    const otros = new Set([...(d.amigos || []), ...(d.sol_rec || []).map((x) => x.de), ...(d.sol_env || []).map((x) => x.a)]);
    for (const u of otros) {
      if (!u || u === viejo) continue;
      try {
        await actualizar(u, (cu) => {
          const cambia = (x) => (x === viejo ? nuevo : x);
          cu.amigos = (cu.amigos || []).map(cambia).filter(Boolean);
          cu.sol_rec = (cu.sol_rec || []).map((s) => ({ ...s, de: cambia(s.de) })).filter((s) => s.de);
          cu.sol_env = (cu.sol_env || []).map((s) => ({ ...s, a: cambia(s.a) })).filter((s) => s.a);
          return {};
        });
      } catch (e) { console.error('[admin] amigos de', u, e.message); }
    }
  }

  // -------------------------------------------------------------------- las rutas
  async function rutas(req, res, ruta, url, ip) {
    if (!ADMIN_HASH) return responder(res, 503, { error: 'el panel no esta configurado en el servidor (BREACH_ADMIN_HASH)' });

    if (ruta === '/admin/entrar' && req.method === 'POST') {
      // 5 intentos cada 15 minutos por IP, y 30 a la hora entre todas: la clave no se adivina a fuerza de probar
      if (demasiado('adm:' + ip, 5, 900000) || demasiado('adm:*', 30, 3600000))
        return responder(res, 429, { error: 'demasiados intentos: espera un rato' });
      const b = await leerCuerpo(req);
      if (!claveCorrecta(b.clave)) {
        console.log('[admin] clave incorrecta desde', ip);
        await new Promise((r) => setTimeout(r, 600));
        return responder(res, 401, { error: 'clave incorrecta' });
      }
      console.log('[admin] sesion abierta desde', ip);
      return responder(res, 200, { token: firmarAdmin(), horas: HORAS_ADMIN });
    }

    if (!tokenAdminValido(req)) return responder(res, 401, { error: 'sesion del panel caducada' });
    await cargarTodos(false);
    const quien = (u) => console.log('[admin]', ip, ruta, u || '');

    // ---- resumen del servidor
    if (ruta === '/admin/resumen') {
      const { cuentas } = await todasLasCuentas();
      const ahora = Date.now();
      let enLinea = 0, jugando = 0;
      for (const p of presencia.values()) {
        if (ahora - p.t < PRESENCIA_VIVA_MS) { enLinea++; if (p.donde === 'partida') jugando++; }
      }
      const hoy = cuentas.filter((c) => ahora - c.t < 86400000).length;
      return responder(res, 200, {
        cuentas: cuentas.length, google: cuentas.filter((c) => c.nombre.startsWith('g_')).length,
        activas_hoy: hoy, en_linea: enLinea, jugando, salas: salas.size,
        regalos_todos: todos.lista.filter((g) => g.hasta > ahora).map((g) => ({ ...regaloPublico(g), hasta: new Date(g.hasta).toISOString() })),
        articulos: Object.keys(PRECIOS).length,
      });
    }

    // ---- el catalogo de la tienda (para regalar articulos)
    if (ruta === '/admin/catalogo') {
      const lista = Object.keys(PRECIOS).sort().map((k) => ({ clave: k, precio: tienda.precioDe(k),
        nombre: nombreArticulo(k), tipo: (CATALOGO[k] || {}).t || '' }));
      return responder(res, 200, { articulos: lista });
    }

    // ---- EN VIVO: las salas abiertas y quien esta conectado (lobby o partida), y con que cuenta se especta
    if (ruta === '/admin/vivo' && req.method === 'GET') {
      espectar.limpiarSalas();
      const ahora = Date.now();
      const lista = [...salas.values()].sort((a, b2) => (b2.jugadores - a.jugadores)).slice(0, 50).map((s) => ({
        id: s.id, nombre: s.nombre || 'Sala', anfitrion: s.anfitrion || '', mapa: s.mapa || '', modo: s.modo || '',
        jugadores: s.jugadores || 0, max: s.max || 0, jugando: s.jugando === true, abierta: espectar.alcanzable(s),
        desde: Math.round((ahora - (s.creada || s.visto || ahora)) / 1000),
      }));
      const vivos = [...presencia.entries()].filter(([, p]) => ahora - p.t < PRESENCIA_VIVA_MS)
        .sort((a, b2) => b2[1].t - a[1].t).slice(0, 60);
      const datos = await Promise.all(vivos.map(([u]) => cuentaAjena(u).catch(() => null)));
      const jugadores = vivos.map(([u, p], i) => ({ usuario: u, nombre: (datos[i] && datos[i].nombre) || u,
        donde: p.donde, hace: Math.round((ahora - p.t) / 1000) }));
      const cfg = await espectar.leerConfig();
      return responder(res, 200, { salas: lista, jugadores, espectador: cfg.espectador || '' });
    }

    // ---- LA TIENDA: cada articulo con su nombre y precio de ahora y los de fabrica (para editarlos)
    if (ruta === '/admin/tienda' && req.method === 'GET') {
      return responder(res, 200, { v: tienda.ajustes().v, articulos: Object.keys(PRECIOS).sort().map(articuloTienda) });
    }

    // ---- LOS AJUSTES DEL JUEGO (cofres, cartas, personajes, oro, pase) y los DESTACADOS: lo de fabrica, lo que puso el
    // panel y lo que vale ahora; y la lista de articulos para elegir (pools de cofres, destacados, premios del pase)
    if (ruta === '/admin/juego' && req.method === 'GET') {
      const aj = tienda.ajustes();
      const fabrica = tienda.juegoFabrica();
      const actual = aj.juego || {};
      const efectivo = {};
      for (const k of Object.keys(fabrica)) efectivo[k] = actual[k] !== undefined && actual[k] !== null ? actual[k] : fabrica[k];
      const articulos = Object.keys(PRECIOS).sort().map((k) => ({ clave: k, tipo: (CATALOGO[k] || {}).t || '',
        nombre: tienda.nombreDe(k), precio: tienda.precioDe(k) }));
      return responder(res, 200, { v: aj.v, fabrica, actual, efectivo, destacados: aj.destacados || [], articulos });
    }

    // ---- la lista, con busqueda y paginas
    if (ruta === '/admin/cuentas') {
      // ?hoy=1: las activas en las ultimas 24 h (la tarjeta "Activas hoy" del resumen), de la mas reciente a la mas vieja
      const encontrados = url.searchParams.get('hoy') === '1'
        ? (await todasLasCuentas()).cuentas.filter((c) => Date.now() - c.t < 86400000).map((c) => c.nombre)
        : await buscar(url.searchParams.get('q'));
      const paginas = Math.max(1, Math.ceil(encontrados.length / POR_PAGINA));
      const pagina = Math.max(0, Math.min(paginas - 1, parseInt(url.searchParams.get('pagina') || '0', 10) || 0));
      const trozo = encontrados.slice(pagina * POR_PAGINA, (pagina + 1) * POR_PAGINA);
      const datos = await Promise.all(trozo.map((u) => cuentaAjena(u).catch(() => null)));
      const lista = [];
      trozo.forEach((u, i) => { if (datos[i]) lista.push(resumen(u, datos[i])); });
      return responder(res, 200, { total: encontrados.length, pagina, paginas, cuentas: lista });
    }

    // ---- una cuenta entera
    if (ruta === '/admin/cuenta' && req.method === 'GET') {
      const u = String(url.searchParams.get('u') || '');
      if (!USUARIO_OK.test(u)) return responder(res, 400, { error: 'usuario no valido' });
      const e = await leer(objetoDe(u));
      if (!e) return responder(res, 404, { error: 'esa cuenta no existe' });
      aCache(u, e.datos, e.generacion);
      if (reportes) await reportes.cargar(false);        // sus reportes en contra, al dia
      return responder(res, 200, { cuenta: ficha(u, e.datos) });
    }

    // ---- LOS REPORTES DE JUGADORES (reportes.js): la lista con filtros (o por los mas reportados) y uno entero
    if (ruta === '/admin/reportes' && req.method === 'GET') {
      const q = Object.fromEntries(['estado', 'reportado', 'motivo', 'orden', 'pagina'].map((k) => [k, url.searchParams.get(k) || '']));
      return responder(res, 200, await reportes.lista(q));
    }
    if (ruta === '/admin/reporte' && req.method === 'GET') {
      const d = await reportes.detalle(String(url.searchParams.get('id') || '').replace(/[^a-f0-9]/g, '').slice(0, 40));
      if (!d) return responder(res, 404, { error: 'ese reporte no existe' });
      return responder(res, 200, d);
    }

    // ---- LOS MENSAJES DE LOS JUGADORES (contacto.js: HABLAR CON NOSOTROS del juego): la lista con filtros y uno entero
    if (ruta === '/admin/mensajes' && req.method === 'GET') {
      if (!contacto) return responder(res, 404, { error: 'no existe' });
      const q = Object.fromEntries(['estado', 'tipo', 'pagina'].map((k) => [k, url.searchParams.get(k) || '']));
      return responder(res, 200, await contacto.lista(q));
    }
    if (ruta === '/admin/mensaje' && req.method === 'GET') {
      if (!contacto) return responder(res, 404, { error: 'no existe' });
      const d = await contacto.detalle(String(url.searchParams.get('id') || '').replace(/[^a-f0-9]/g, '').slice(0, 40));
      if (!d) return responder(res, 404, { error: 'ese mensaje no existe' });
      return responder(res, 200, d);
    }

    // a partir de aqui todo escribe: cuerpo JSON
    if (req.method !== 'POST') return responder(res, 404, { error: 'no existe' });
    const b = await leerCuerpo(req, 65536);      // (el pase entero o los premios de los cofres caben de sobra)
    const u = String(b.u || '');
    // el usuario ES el nombre del fichero: solo lo que puede ser un usuario (las de Google, "g_" + hash)
    if (b.u !== undefined && !USUARIO_OK.test(u)) return responder(res, 400, { error: 'usuario no valido' });

    // ---- LOS CODIGOS (2026-10-15, pedido: "canjear codigos desde el lobby; crearlos desde el panel, de un solo uso o
    // uno por cuenta, con los articulos que quiera"). Cada codigo es un objeto `codigos/<CODIGO>.json`:
    //   { codigo, modo: 'unico' (lo canjea UNA persona) | 'cuenta' (cada cuenta una vez), usos_max (0 = sin tope; en
    //     'unico' siempre 1), hasta (ISO o null), items: [regalos como los del panel], usados: [usuario...], creado, nota }
    // Al canjear, sus articulos entran como REGALOS de la cuenta (el lobby los enseña y los reclama como siempre).
    if (ruta === '/admin/codigos') {
      const nombres = await listar('codigos/');
      const lista = [];
      for (const n of nombres.slice(0, 500)) {
        const e = await leer(claveCodigo(n.nombre));
        if (e && e.datos) lista.push(codigoPublico(e.datos));
      }
      lista.sort((x, y) => String(y.creado).localeCompare(String(x.creado)));
      return responder(res, 200, { codigos: lista });
    }
    if (ruta === '/admin/codigo') {
      const cod = normalizarCodigo(b.codigo);
      if (!cod) return responder(res, 400, { error: 'el codigo: de 4 a 24 letras, numeros o guiones' });
      const items = [];
      for (const it of (Array.isArray(b.items) ? b.items : []).slice(0, 20)) {
        const g = regaloDe(Object.assign({}, it, { mensaje: 'Código ' + cod }));
        if (g.error) return responder(res, 400, { error: g.error });
        items.push(g.regalo);
      }
      if (!items.length) return responder(res, 400, { error: 'el codigo no da nada: añade al menos un articulo' });
      const modo = b.modo === 'unico' ? 'unico' : 'cuenta';
      const dias = parseInt(b.dias, 10);
      const ant = await leer(claveCodigo(cod));
      const d = {
        codigo: cod, modo, usos_max: modo === 'unico' ? 1 : Math.max(0, Math.min(1000000, parseInt(b.usos_max, 10) || 0)),
        hasta: dias > 0 ? new Date(Date.now() + Math.min(3650, dias) * 86400000).toISOString() : null,
        items, nota: limpio(b.nota, 80), usados: ant && ant.datos ? (ant.datos.usados || []) : [],
        creado: ant && ant.datos ? ant.datos.creado : new Date().toISOString(), editado: new Date().toISOString(),
      };
      await escribir(claveCodigo(cod), d, null);
      quien('codigo ' + cod + ' (' + items.map(textoRegalo).join(', ') + ')');
      return responder(res, 200, { codigo: codigoPublico(d) });
    }
    if (ruta === '/admin/codigo/borrar') {
      const cod = normalizarCodigo(b.codigo);
      if (!cod) return responder(res, 400, { error: 'codigo no valido' });
      await borrarObjeto(claveCodigo(cod));
      quien('codigo borrado ' + cod);
      return responder(res, 200, { ok: true });
    }

    // ---- editar: nombre, exp, nivel, oro, diamantes, partidas, articulos, bloqueo
    if (ruta === '/admin/cuenta') {
      const c = b.cambios && typeof b.cambios === 'object' ? b.cambios : {};
      const act = await leer(objetoDe(u));
      if (!act) return responder(res, 404, { error: 'esa cuenta no existe' });
      // EL NOMBRE que se ve es UNICO: se reserva antes de tocar la cuenta (como /nombre)
      let nombreNuevo = null, nombreViejo = '';
      if (c.nombre !== undefined && String(c.nombre).trim() !== act.datos.nombre) {
        nombreNuevo = normalizarNombre(c.nombre);
        if (!nombreNuevo) return responder(res, 400, { error: 'nombre: de 3 a 16 letras o numeros, sin espacios dobles' });
        if (!(await reservarNombre(nombreNuevo, u))) return responder(res, 409, { error: 'ese nombre ya lo tiene otro jugador' });
        nombreViejo = act.datos.nombre_elegido ? act.datos.nombre : '';
      }
      const r = await actualizar(u, (cu) => {
        const hechos = [];
        if (nombreNuevo) { hechos.push(`nombre ${cu.nombre} → ${nombreNuevo}`); cu.nombre = nombreNuevo; cu.nombre_elegido = true; }
        if (c.nivel !== undefined) {
          const n = Math.max(1, Math.min(1000, parseInt(c.nivel, 10) || 1));
          if (n !== nivelDe(cu.exp)) { hechos.push(`nivel ${nivelDe(cu.exp)} → ${n}`); cu.exp = expDeNivel(n); }
        }
        for (const [k, que] of [['exp', 'EXP'], ['monedas', 'oro'], ['creditos', 'diamantes'], ['partidas', 'partidas'], ['ganadas', 'ganadas']]) {
          if (c[k] === undefined) continue;
          const v = numero(c[k]);
          if (v === null) return { error: `${que}: no es un numero` };
          if (v !== (cu[k] || 0)) { hechos.push(`${que} ${cu[k] || 0} → ${v}`); cu[k] = v; }
        }
        // SUMAR / RESTAR (el panel manda la diferencia): no pisa lo que el jugador gane mientras tanto
        if (c.sumar && typeof c.sumar === 'object') {
          for (const [k, que] of [['exp', 'EXP'], ['monedas', 'oro'], ['creditos', 'diamantes']]) {
            if (c.sumar[k] === undefined) continue;
            const d = Math.trunc(Number(c.sumar[k]));
            if (!Number.isFinite(d) || Math.abs(d) > TOPE_NUMERO) return { error: `${que}: no es un numero` };
            if (d === 0) continue;
            const antes = cu[k] || 0;
            cu[k] = Math.max(0, Math.min(TOPE_NUMERO, antes + d));
            hechos.push(`${que} ${d > 0 ? '+' : ''}${d} (${antes} → ${cu[k]})`);
          }
        }
        // AÑADIR / QUITAR articulos sueltos (lo que compre entretanto se queda)
        for (const [lista, mas] of [[c.armas_mas, true], [c.armas_menos, false]]) {
          if (!Array.isArray(lista)) continue;
          cu.armas = cu.armas || [];
          for (const x of lista.map((y) => String(y).slice(0, 48)).filter(Boolean).slice(0, 100)) {
            if (mas && !cu.armas.includes(x)) {
              if (!Object.prototype.hasOwnProperty.call(PRECIOS, x)) return { error: 'ese articulo no existe en la tienda' };
              cu.armas.push(x);
              hechos.push('+ ' + nombreArticulo(x));
            } else if (!mas && cu.armas.includes(x)) {
              cu.armas = cu.armas.filter((y) => y !== x);
              hechos.push('− ' + nombreArticulo(x));
            }
          }
        }
        if (Array.isArray(c.armas)) {
          const nuevas = [...new Set(c.armas.map((x) => String(x).slice(0, 48)).filter(Boolean))].slice(0, 600);
          const antes = new Set(cu.armas || []);
          const mas = nuevas.filter((x) => !antes.has(x)), menos = [...antes].filter((x) => !nuevas.includes(x));
          if (mas.length) hechos.push('articulos + ' + mas.map(nombreArticulo).join(', '));
          if (menos.length) hechos.push('articulos − ' + menos.map(nombreArticulo).join(', '));
          cu.armas = nuevas;
        }
        if (c.bloqueada !== undefined && !!c.bloqueada !== !!cu.bloqueada) {
          cu.bloqueada = !!c.bloqueada;
          cu.motivo_bloqueo = cu.bloqueada ? limpio(c.motivo, 120) : '';
          hechos.push(cu.bloqueada ? `BLOQUEADA${cu.motivo_bloqueo ? ': ' + cu.motivo_bloqueo : ''}` : 'desbloqueada');
        }
        if (!hechos.length) return { nada: true };
        apuntar(cu, hechos.join(' · '));
        return { hechos };
      });
      if (r.error) {
        if (nombreNuevo) await soltarNombre(nombreNuevo);
        return responder(res, r.error === 'no existe' ? 404 : 400, { error: r.error });
      }
      if (nombreNuevo && nombreViejo && nombreViejo !== nombreNuevo) await soltarNombre(nombreViejo);
      ctx.avisarCambio(u);
      // bloqueada o desbloqueada: el juego de esa cuenta se entera en su siguiente latido (index.js, `bloqueos`)
      if (ctx.avisarBloqueo && r.cuenta) ctx.avisarBloqueo(u, !!r.cuenta.bloqueada, r.cuenta.motivo_bloqueo || '');
      quien(u + ' ' + ((r.extra && r.extra.hechos) || []).join(' · '));
      return responder(res, 200, { cuenta: ficha(u, r.cuenta) });
    }

    // ---- LA CUENTA DEL JUEGO CON LA QUE ESPECTA EL ADMINISTRADOR ("" = ninguna)
    if (ruta === '/admin/espectador') {
      const q = String(b.usuario || '').trim().toLowerCase();
      if (q && !USUARIO_OK.test(q)) return responder(res, 400, { error: 'usuario no valido' });
      if (q && !(await leer(objetoDe(q)))) return responder(res, 404, { error: 'esa cuenta del juego no existe' });
      const cfg = { ...(await espectar.leerConfig()), espectador: q };
      await espectar.guardarConfig(cfg);
      quien('espectador ' + (q || '(ninguno)'));
      return responder(res, 200, { espectador: q });
    }
    // ---- ESPECTAR UNA SALA: se apunta la orden para la cuenta del juego del administrador (ver ESPECTAR en index.js)
    // Desde el telefono (`aparato`: la huella de este movil) la orden es para el Breach de ESTE movil, con la cuenta que
    // tenga abierta; sin ella (el panel en el PC), para la cuenta configurada.
    if (ruta === '/admin/espectar') {
      const cfg = await espectar.leerConfig();
      const aparato = String(b.aparato || '');
      const porAparato = /^[a-f0-9]{16,64}$/.test(aparato);
      if (!porAparato && !cfg.espectador) return responder(res, 400, { error: 'configura primero tu cuenta del juego' });
      espectar.limpiarSalas();
      const s = salas.get(String(b.sala || ''));
      if (!s) return responder(res, 404, { error: 'esa sala ya no existe' });
      espectar.ordenar(porAparato ? '' : cfg.espectador, s, porAparato ? aparato : '');
      quien(`espectar ${s.id} (${s.mapa}) ${porAparato ? 'desde este movil' : 'con ' + cfg.espectador}`);
      return responder(res, 200, { ok: true, espectador: porAparato ? '' : cfg.espectador, por_aparato: porAparato,
        paquete: 'com.breach.voxelfps' });
    }

    // ---- UN MENSAJE DE UN JUGADOR: nuevo, leido o hecho ({id, estado, nota})
    if (ruta === '/admin/mensaje/estado') {
      if (!contacto) return responder(res, 404, { error: 'no existe' });
      const r = await contacto.cambiarEstado(String(b.id || '').replace(/[^a-f0-9]/g, '').slice(0, 40), String(b.estado || ''), b.nota);
      if (r.error) return responder(res, r.error === 'ese mensaje no existe' ? 404 : 400, { error: r.error });
      quien(`mensaje ${r.mensaje.id}: ${r.mensaje.estado}`);
      return responder(res, 200, await contacto.detalle(r.mensaje.id));
    }

    // ---- UN REPORTE: pendiente, revisado o descartado ({id, estado, nota})
    if (ruta === '/admin/reporte/estado') {
      const r = await reportes.cambiarEstado(String(b.id || '').replace(/[^a-f0-9]/g, '').slice(0, 40), String(b.estado || ''), b.nota);
      if (r.error) return responder(res, r.error === 'ese reporte no existe' ? 404 : 400, { error: r.error });
      quien(`reporte ${r.reporte.id} ${r.reporte.a.u}: ${r.reporte.estado}`);
      return responder(res, 200, await reportes.detalle(r.reporte.id));
    }

    // ---- CAMBIAR EL NOMBRE O EL PRECIO DE UN ARTICULO. "" = el nombre de fabrica; 0 = el precio de fabrica.
    if (ruta === '/admin/tienda') {
      const k = String(b.clave || '').slice(0, 48);
      if (!Object.prototype.hasOwnProperty.call(PRECIOS, k)) return responder(res, 400, { error: 'ese articulo no existe en la tienda' });
      const aj = tienda.ajustes();
      const nueva = { precios: { ...aj.precios }, nombres: { ...aj.nombres } };   // guardar() conserva juego y destacados
      const hechos = [];
      if (b.nombre !== undefined) {
        const n = limpio(b.nombre, 40);
        if ((CATALOGO[k] || {}).t === 'habilidad' && n) return responder(res, 400, { error: 'el nombre de una habilidad no se cambia' });
        const orig = (CATALOGO[k] && CATALOGO[k].n) || k;
        if (!n || n === orig) delete nueva.nombres[k]; else nueva.nombres[k] = n;
        hechos.push(`nombre ${tienda.nombreDe(k)} → ${nueva.nombres[k] || orig}`);
      }
      if (b.precio !== undefined) {
        const p = parseInt(b.precio, 10);
        if (!Number.isFinite(p) || p < 0 || p > 10000000) return responder(res, 400, { error: 'precio: de 1 a 10.000.000' });
        if (!p || p === PRECIOS[k]) delete nueva.precios[k]; else nueva.precios[k] = p;
        hechos.push(`precio ${tienda.precioDe(k)} → ${nueva.precios[k] || PRECIOS[k]}`);
      }
      if (!hechos.length) return responder(res, 400, { error: 'no hay nada que cambiar' });
      await tienda.guardar(nueva);
      quien(`tienda ${k}: ${hechos.join(' · ')}`);
      return responder(res, 200, { articulo: articuloTienda(k) });
    }

    // ---- LOS PACKS DE pagos (desactivados) (2026-10-28, pedido: "no puedo modificar el precio con el panel"): GET la lista;
    // POST {id, precio}: precio en pesos (con centavos), 0 = no se vende, null = el de fabrica
    if (ruta === '/admin/packs') {
      const aj = tienda.ajustes();
      if (b.id !== undefined) {
        const id = String(b.id);
        const pk = tienda.PACKS[id];
        if (!pk || pk.retirado) return responder(res, 400, { error: 'ese pack no existe' });
        const packs = { ...(aj.packs || {}) };
        if (b.precio === null || b.precio === undefined || b.precio === '') delete packs[id];
        else {
          const p = Math.round(Number(b.precio) * 100) / 100;
          if (!Number.isFinite(p) || p < 0 || p > 100000000) return responder(res, 400, { error: 'precio: de 0 a 100.000.000' });
          packs[id] = p === 0 ? -1 : p;
        }
        await tienda.guardar({ packs });
        quien(`pack ${id}: ${packs[id] === undefined ? 'de fabrica' : packs[id]}`);
      }
      const pr = tienda.preciosPacks();
      const panel = tienda.ajustes().packs || {};
      const lista = Object.entries(tienda.PACKS).filter(([, p]) => !p.retirado).map(([id, p]) => ({
        id, nombre: p.nombre, creditos: p.creditos || 0, cubos: p.cubos || 0, unico: !!p.unico,
        fabrica: Number(p.ars) || 0, precio: Number(pr[id]) || 0, del_panel: Object.prototype.hasOwnProperty.call(panel, id) }));
      return responder(res, 200, { moneda: tienda.moneda(), packs: lista });
    }
    // ---- CAMBIAR UN AJUSTE DEL JUEGO ({clave, valor}; valor null = el de fabrica)
    if (ruta === '/admin/juego') {
      const k = String(b.clave || '');
      const aj = tienda.ajustes();
      const juego = { ...(aj.juego || {}) };
      if (b.valor === null || b.valor === undefined) {
        if (!Object.prototype.hasOwnProperty.call(tienda.juegoFabrica(), k)) return responder(res, 400, { error: 'ese ajuste no existe' });
        delete juego[k];
      } else {
        const r = tienda.validarJuego(k, b.valor);
        if (r.error) return responder(res, 400, { error: r.error });
        juego[k] = r.valor;
      }
      await tienda.guardar({ juego });
      quien(`juego ${k}: ${b.valor === null || b.valor === undefined ? 'de fabrica' : 'cambiado'}`);
      return responder(res, 200, { v: tienda.ajustes().v, clave: k, valor: juego[k] === undefined ? null : juego[k] });
    }
    // ---- LOS DESTACADOS DE LA TIENDA ({lista: [{clave, precio, moneda}]}, hasta 8; [] = ninguno)
    if (ruta === '/admin/destacados') {
      const r = tienda.validarDestacados(b.lista);
      if (r.error) return responder(res, 400, { error: r.error });
      await tienda.guardar({ destacados: r.valor });
      quien(`destacados: ${r.valor.map((d) => d.clave + ' ' + d.precio + (d.moneda === 'creditos' ? ' diam.' : ' oro')).join(', ') || '(ninguno)'}`);
      return responder(res, 200, { v: tienda.ajustes().v, destacados: r.valor });
    }

    // ---- poner una contraseña nueva (solo cuentas con usuario y clave: las de Google entran con Google)
    if (ruta === '/admin/clave') {
      if (!claveValida(b.clave)) return responder(res, 400, { error: 'la clave necesita de 6 a 72 caracteres' });
      const r = await actualizar(u, (cu) => {
        if (cu.google) return { error: 'es una cuenta de Google: no tiene contraseña, entra con Google' };
        cu.sal = crypto.randomBytes(16).toString('hex');
        cu.hash = hashClave(b.clave, cu.sal);
        apuntar(cu, 'contraseña cambiada');
        return {};
      });
      if (r.error) return responder(res, r.error === 'no existe' ? 404 : 400, { error: r.error });
      quien(u + ' clave');
      return responder(res, 200, { cuenta: ficha(u, r.cuenta) });
    }

    // ---- cambiar el USUARIO (con el que se entra). El nombre del fichero ES el usuario: se copia la cuenta al
    // nombre nuevo (solo si esta libre), se mueven los indices (ID y nombre) y las listas de amigos de los demas,
    // y se borra la vieja. Su sesion abierta caduca: tiene que volver a entrar con el usuario nuevo.
    if (ruta === '/admin/usuario') {
      const nuevo = normalizarUsuario(b.nuevo);
      if (!nuevo) return responder(res, 400, { error: 'usuario: 3-16 letras minusculas, numeros, _ o - (no puede empezar por g_)' });
      if (u.startsWith('g_')) return responder(res, 400, { error: 'las cuentas de Google no tienen usuario: se entra con Google' });
      if (nuevo === u) return responder(res, 400, { error: 'es el mismo usuario' });
      const act = await leer(objetoDe(u));
      if (!act) return responder(res, 404, { error: 'esa cuenta no existe' });
      const copia = JSON.parse(JSON.stringify(act.datos));
      copia.usuario = nuevo;
      apuntar(copia, `usuario ${u} → ${nuevo}`);
      const gen = await escribir(objetoDe(nuevo), copia, '0');
      if (gen === null) return responder(res, 409, { error: 'ese usuario ya existe' });
      if (copia.id_pub) await escribir(claveId(copia.id_pub), { usuario: nuevo }, null);
      if (copia.nombre) {
        const res2 = await leer(claveNombre(copia.nombre));
        if (res2 && res2.datos && res2.datos.usuario === u)
          await escribir(claveNombre(copia.nombre), { ...res2.datos, usuario: nuevo }, null);
      }
      await arreglarAmigos(copia, u, nuevo);
      await borrarObjeto(objetoDe(u));
      borrarCache(u);
      aCache(nuevo, copia, gen);
      olvidarLista();
      quien(`${u} -> ${nuevo}`);
      return responder(res, 200, { cuenta: ficha(nuevo, copia) });
    }

    // ---- un regalo a una cuenta
    if (ruta === '/admin/regalo') {
      const g = regaloDe(b);
      if (g.error) return responder(res, 400, { error: g.error });
      const r = await actualizar(u, (cu) => {
        if ((cu.regalos || []).length >= REGALOS_MAX) return { error: `ya tiene ${REGALOS_MAX} regalos sin reclamar` };
        cu.regalos = (cu.regalos || []).concat([g.regalo]);
        apuntar(cu, 'regalo: ' + textoRegalo(g.regalo) + (g.regalo.mensaje ? ` ("${g.regalo.mensaje}")` : ''));
        return {};
      });
      if (r.error) return responder(res, r.error === 'no existe' ? 404 : 400, { error: r.error });
      ctx.avisarCambio(u);
      quien(u + ' regalo ' + textoRegalo(g.regalo));
      return responder(res, 200, { cuenta: ficha(u, r.cuenta) });
    }
    if (ruta === '/admin/regalo/quitar') {
      const id = String(b.id || '');
      const r = await actualizar(u, (cu) => {
        const g = (cu.regalos || []).find((x) => x.id === id);
        if (!g) return { error: 'ese regalo ya no esta (¿lo reclamo?)' };
        cu.regalos = cu.regalos.filter((x) => x.id !== id);
        apuntar(cu, 'regalo retirado: ' + textoRegalo(g));
        return {};
      });
      if (r.error) return responder(res, 400, { error: r.error });
      ctx.avisarCambio(u);
      return responder(res, 200, { cuenta: ficha(u, r.cuenta) });
    }

    // ---- un regalo a TODOS (los que entren antes de que caduque)
    if (ruta === '/admin/regalo_todos') {
      const g = regaloDe(b);
      if (g.error) return responder(res, 400, { error: g.error });
      const dias = Math.max(1, Math.min(90, parseInt(b.dias, 10) || 7));
      await cargarTodos(true);
      if (todos.lista.length >= 20) return responder(res, 400, { error: 'ya hay 20 regalos a todos activos' });
      todos.lista.push({ ...g.regalo, hasta: Date.now() + dias * 86400000 });
      await guardarTodos();
      quien('TODOS regalo ' + textoRegalo(g.regalo) + ` ${dias} dias`);
      return responder(res, 200, { ok: true, version: todos.version });
    }
    if (ruta === '/admin/regalo_todos/quitar') {
      await cargarTodos(true);
      const antes = todos.lista.length;
      todos.lista = todos.lista.filter((g) => g.id !== String(b.id || ''));
      if (todos.lista.length === antes) return responder(res, 404, { error: 'ese regalo ya no esta' });
      await guardarTodos();
      quien('TODOS quitar ' + b.id);
      return responder(res, 200, { ok: true });
    }

    // ---- crear una cuenta (usuario y clave)
    if (ruta === '/admin/crear') {
      const usuario = normalizarUsuario(b.usuario);
      if (!usuario) return responder(res, 400, { error: 'usuario: 3-16 letras minusculas, numeros, _ o -' });
      if (!claveValida(b.clave)) return responder(res, 400, { error: 'la clave necesita de 6 a 72 caracteres' });
      const nombre = normalizarNombre(b.nombre || usuario);
      if (!nombre) return responder(res, 400, { error: 'nombre: de 3 a 16 letras o numeros' });
      const sal = crypto.randomBytes(16).toString('hex');
      const ahora = new Date().toISOString();
      const cuenta = {
        usuario, nombre, sal, hash: hashClave(b.clave, sal), exp: 0, monedas: 0, armas: [], partidas: 0, ganadas: 0,
        nombre_elegido: true, creada: ahora, ultima: ahora, recientes: [],
        registro_admin: [{ t: ahora, que: 'creada desde el panel' }],
      };
      const gen = await escribir(objetoDe(usuario), cuenta, '0');
      if (gen === null) return responder(res, 409, { error: 'ese usuario ya existe' });
      if (!(await reservarNombre(nombre, usuario))) {
        cuenta.nombre_elegido = false;           // el nombre lo tiene otro: que lo elija al entrar
        await escribir(objetoDe(usuario), cuenta, null);
      }
      aCache(usuario, cuenta, gen);
      olvidarLista();
      quien(usuario + ' creada');
      return responder(res, 200, { cuenta: ficha(usuario, cuenta) });
    }

    // ---- borrar una cuenta: sin vuelta atras. Hay que mandar el usuario dos veces (la app lo pide escrito).
    if (ruta === '/admin/borrar') {
      if (!u || String(b.confirmar || '') !== u) return responder(res, 400, { error: 'hay que confirmar escribiendo el usuario' });
      const act = await leer(objetoDe(u));
      if (!act) return responder(res, 404, { error: 'esa cuenta no existe' });
      const d = act.datos;
      if (d.nombre) {
        const rn = await leer(claveNombre(d.nombre));
        if (rn && rn.datos && rn.datos.usuario === u) await soltarNombre(d.nombre);
      }
      if (d.id_pub) {
        const ri = await leer(claveId(d.id_pub));
        if (ri && ri.datos && ri.datos.usuario === u) await borrarObjeto(claveId(d.id_pub));
      }
      await arreglarAmigos(d, u, null);
      await borrarObjeto(objetoDe(u));
      borrarCache(u);
      olvidarLista();
      quien(u + ' BORRADA');
      return responder(res, 200, { ok: true });
    }

    return responder(res, 404, { error: 'no existe' });
  }

  // -------------------------------------------------------------------- lo que usa el resto del servidor
  return {
    rutas, cargarTodos, regalosPendientes, tokenAdminValido, regaloDe,
    regalosPublicos: (cu) => regalosPendientes(cu).map(regaloPublico),
    versionTodos: () => todos.version || 0,
    /** CANJEAR UN CODIGO: comprueba que vale y que esta cuenta no lo uso, lo apunta en el codigo (solo si nadie lo ha
     * cambiado entretanto: generacion) y mete sus articulos como regalos de la cuenta. {ok, regalos} o {error}. */
    async canjear(usuario, codigo) {
      const cod = normalizarCodigo(codigo);
      if (!cod) return { error: 'ese código no es válido' };
      for (let intento = 0; intento < 4; intento++) {
        const e = await leer(claveCodigo(cod));
        if (!e || !e.datos) return { error: 'ese código no existe' };
        const d = e.datos;
        if (d.hasta && Date.parse(d.hasta) < Date.now()) return { error: 'ese código ha caducado' };
        const usados = d.usados || [];
        if (usados.includes(usuario)) return { error: 'ya canjeaste este código' };
        if (d.usos_max > 0 && usados.length >= d.usos_max) return { error: d.modo === 'unico' ? 'ese código ya lo canjeó otra persona' : 'ese código ya se agotó' };
        d.usados = usados.concat([usuario]);
        if ((await escribir(claveCodigo(cod), d, e.generacion)) === null) continue;     // otro lo canjeo a la vez: otra vuelta
        const nuevos = (d.items || []).map((g) => Object.assign({}, g, { id: crypto.randomBytes(6).toString('hex'), t: new Date().toISOString() }));
        const r = await actualizar(usuario, (cu) => {
          cu.regalos = (cu.regalos || []).concat(nuevos).slice(-REGALOS_MAX);
          apuntar(cu, 'codigo ' + cod + ': ' + nuevos.map(textoRegalo).join(', '));
          return {};
        });
        if (r.error) return { error: r.error };
        console.log('[codigo]', usuario, 'canjeo', cod);
        return { ok: true, regalos: nuevos.map(regaloPublico) };
      }
      return { error: 'inténtalo otra vez' };
    },
    /** RECLAMAR: el juego pide sus regalos (todos, o los de `ids`). Se suman aqui y solo aqui. */
    async reclamar(usuario, ids) {
      await cargarTodos(false);
      return actualizar(usuario, (cu) => {
        const pend = regalosPendientes(cu);
        const elegidos = Array.isArray(ids) && ids.length ? pend.filter((g) => ids.includes(g.id)) : pend;
        if (!elegidos.length) return { reclamados: [] };
        for (const g of elegidos) {
          aplicarRegalo(cu, g);
          if (g.todos) cu.regalos_vistos = (cu.regalos_vistos || []).concat([g.id]).slice(-VISTOS_MAX);
          else cu.regalos = (cu.regalos || []).filter((x) => x.id !== g.id);
        }
        return { reclamados: elegidos.map(regaloPublico) };
      });
    },
  };
};
