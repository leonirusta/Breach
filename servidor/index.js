'use strict';
/**
 * Servidor de cuentas de Breach.
 *
 * Node puro: ni una dependencia de npm. No es purismo — `npm install` mete decenas de megas en la
 * imagen y el ARRANQUE EN FRIO SE PAGA EN CPU FACTURABLE, que es justo lo que hay que cuidar para no
 * salirse de la capa gratis de Cloud Run. Sin dependencias la imagen es la base de Node y arranca en
 * milisegundos.
 *
 * Los datos son JSON en un bucket de Cloud Storage, UNO POR CUENTA (ver README: por qué no uno solo).
 * Se habla con GCS por su API REST pidiendo el token al servidor de metadatos, asi que no hay ninguna
 * clave guardada en ningun sitio.
 */
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PUERTO = parseInt(process.env.PORT || '8080', 10);
const BUCKET = process.env.BREACH_BUCKET || '';
const SECRETO = process.env.BREACH_SECRET || '';
const LOCAL = process.env.BREACH_LOCAL || '';          // carpeta: modo sin nube, para probar
/**
 * ENTRAR CON GOOGLE. Los dos valores salen de la consola de Google Cloud (APIs y servicios ->
 * Credenciales -> ID de cliente de OAuth, tipo "Aplicacion web").
 *
 * EL SECRETO SE QUEDA AQUI. Podria hacerse el intercambio del codigo en el juego con PKCE, pero
 * entonces el `client_secret` viajaria dentro del .pck y cualquiera puede abrir un .pck. Haciendo el
 * intercambio en el servidor, el juego nunca ve el secreto: solo recibe NUESTRO token al final.
 */
const G_ID = process.env.GOOGLE_CLIENT_ID || '';
const G_SECRET = process.env.GOOGLE_CLIENT_SECRET || '';
/** A donde vuelve Google. Tiene que estar dada de alta TAL CUAL en la consola. */
const G_REDIR = (process.env.BREACH_URL || '') + '/google/callback';
const DIAS_TOKEN = 30;
const CACHE_MS = 30000;

// ---------------------------------------------------------------------------
// PAGOS CON DINERO REAL: DESACTIVADOS en esta version (sin Mercado Pago).
// ---------------------------------------------------------------------------
const MP_TOKEN = '';
const MP_MONEDA = 'ARS';
/**
 * Los packs: cuantos DIAMANTES (creditos) da cada uno. Los mismos ids que `PACKS_MONEDAS` en lobby.gd.
 * LA TIENDA / DINERO (2026-09-30, pedido con capturas de la tienda de Pixel Gun: "mete todas las ofertas que estan ahi"):
 *   dia_*      los de siempre, sin limite.
 *   unico_*    UNICA VEZ · VALOR X2: UNA vez por cuenta (`cu.packs_unicos`) y a mitad de precio: dan el doble de lo que se
 *              paga (`base` es lo que valdria ese dinero en un pack normal). Si llegara un segundo pago de la misma oferta
 *              (dos pagos abiertos a la vez), ese da solo `base`.
 *   `ars`      el precio de fabrica: el de las capturas tal cual, en pesos y con los centavos. MP_PRECIOS lo cambia por id
 *              (0 = no se vende). Solo vale si se cobra en pesos (MP_MONEDA=ARS).
 *   `retirado` los packs de antes: ya no se venden, pero un pago que se quedo abierto se sigue pagando.
 */
const PACKS = {
  // los dos primeros de la captura son CUBOS DE FUERZA (`cubos`), no diamantes: se suman a cu.cubos
  cubos_pack_60:  { nombre: 'Pack de 60 cubos de fuerza', cubos: 60, ars: 8955.05 },
  cubos_pack_100: { nombre: 'Pack de 100 cubos de fuerza', cubos: 100, ars: 14935.05 },
  dia_900:    { nombre: 'Pack de 900 diamantes', creditos: 900, ars: 44835.05 },
  dia_1200:   { nombre: 'Pack de 1.200 diamantes', creditos: 1200, ars: 59785.05 },
  dia_1500:   { nombre: 'Pack de 1.500 diamantes', creditos: 1500, ars: 74735.05 },
  dia_1800:   { nombre: 'Pack de 1.800 diamantes', creditos: 1800, ars: 89685.05 },
  dia_2250:   { nombre: 'Pack de 2.250 diamantes', creditos: 2250, ars: 112110.05 },
  dia_3000:   { nombre: 'Pack de 3.000 diamantes', creditos: 3000, ars: 149485.05 },
  unico_60:   { nombre: 'Unica vez: 60 diamantes (valor x2)', creditos: 60, base: 30, unico: true, ars: 1480.05 },
  unico_300:  { nombre: 'Unica vez: 300 diamantes (valor x2)', creditos: 300, base: 150, unico: true, ars: 7460.05 },
  unico_600:  { nombre: 'Unica vez: 600 diamantes (valor x2)', creditos: 600, base: 300, unico: true, ars: 14935.05 },
  unico_900:  { nombre: 'Unica vez: 900 diamantes (valor x2)', creditos: 900, base: 450, unico: true, ars: 22410.05 },
  unico_1200: { nombre: 'Unica vez: 1.200 diamantes (valor x2)', creditos: 1200, base: 600, unico: true, ars: 29885.05 },
  unico_1500: { nombre: 'Unica vez: 1.500 diamantes (valor x2)', creditos: 1500, base: 750, unico: true, ars: 37360.05 },
  pack_500:  { nombre: 'Bolsa de 500 creditos', creditos: 500, retirado: true },
  pack_1200: { nombre: 'Cofre de 1.200 creditos', creditos: 1200, retirado: true },
  pack_2500: { nombre: 'Baul de 2.500 creditos', creditos: 2500, retirado: true },
  pack_6500: { nombre: 'Caja fuerte de 6.500 creditos', creditos: 6500, retirado: true },
};
/** Lo que cuesta cada pack: el de MP_PRECIOS si lo pone (0 = no se vende); si no, el de fabrica (`ars`, en pesos). */
function preciosPacks() {
  let env = {};
  try { env = JSON.parse(process.env.MP_PRECIOS || '{}') || {}; } catch { env = {}; }
  const out = {};
  for (const [id, p] of Object.entries(PACKS)) {
    // 2026-10-28: el precio del PANEL (admin/tienda.json `packs`) manda sobre MP_PRECIOS y el de fabrica; -1 = no se vende
    const panel = (TIENDA && TIENDA.packs) || {};
    const v = Object.prototype.hasOwnProperty.call(panel, id) ? Number(panel[id])
      : Object.prototype.hasOwnProperty.call(env, id) ? Number(env[id]) : (MP_MONEDA === 'ARS' ? Number(p.ars) : 0);
    out[id] = Number.isFinite(v) && v > 0 ? v : 0;
  }
  return out;
}
/**
 * EL ORO Y LOS CUBOS DE FUERZA CON DIAMANTES (la fila DINERO de la tienda, 2026-09-30). El cambio lo pone ESTA tabla, no
 * el juego (que solo manda el id: /tienda/cambio). Los mismos ids que `TiendaDinero.CAMBIOS` en el juego. El oro, el de la
 * captura tal cual (20 por diamante, y mas cuanto mayor); los cubos, la misma escala a la mitad (un cubo, dos de oro).
 */
const CAMBIOS = {
  // LA ECONOMIA DE UN SOLO CAMBIO (2026-09-30): 10 de oro por diamante y 3 diamantes por cubo, con la rebaja de la carta
  oro_40:     { t: 'oro', n: 40, creditos: 4 },
  oro_440:    { t: 'oro', n: 440, creditos: 40 },
  oro_1830:   { t: 'oro', n: 1830, creditos: 155 },
  oro_4560:   { t: 'oro', n: 4560, creditos: 365 },
  oro_9300:   { t: 'oro', n: 9300, creditos: 700 },
  cubos_5:    { t: 'cubos', n: 5, creditos: 15 },
  cubos_25:   { t: 'cubos', n: 25, creditos: 68 },
  cubos_60:   { t: 'cubos', n: 60, creditos: 153 },
  cubos_150:  { t: 'cubos', n: 150, creditos: 360 },
  cubos_400:  { t: 'cubos', n: 400, creditos: 900 },
};
/** LO GRATIS de la tienda: 5 de oro cada 4 horas y un cofre COMUN (rareza 0) cada 24. El reloj lo lleva la cuenta (el
 * momento del ultimo, en `campo`). BREACH_GRATIS_MS acorta los dos relojes (solo para las pruebas). */
const GRATIS = {
  oro: { ms: Number(process.env.BREACH_GRATIS_MS) || 4 * 3600000, campo: 'oro_gratis_t' },
  cofre: { ms: Number(process.env.BREACH_GRATIS_MS) || 24 * 3600000, campo: 'cofre_gratis_t' },
};
const ORO_GRATIS = 5;
/** Lo que falta (ms) para poder reclamar lo gratis `que` (0 = ya) */
function gratisRestante(c, que, ahora) {
  return Math.max(0, (Number(c[GRATIS[que].campo]) || 0) + GRATIS[que].ms - ahora);
}

if (!SECRETO) { console.error('FALTA BREACH_SECRET'); process.exit(1); }
if (!BUCKET && !LOCAL) { console.error('FALTA BREACH_BUCKET (o BREACH_LOCAL para probar)'); process.exit(1); }

// ---------------------------------------------------------------------------
// PREMIOS. Viven AQUI y el cliente no los conoce.
//
// El cliente manda lo que PASO ("gane en oleadas, oleada 10, 47 bajas"), nunca lo que ha ganado. Si
// mandara el premio, cualquiera con un proxy manda seiscientos mil. Esta es la unica cuenta.
// ---------------------------------------------------------------------------
// La EXPERIENCIA sigue por modo. Las MONEDAS ya no: salen de `monedasDePartida`, igual en todos los modos.
const PREMIOS = {
  pve:    (r) => ({ exp: 600 + r.bajas * 4 + Math.floor(r.puntos / 10) + r.oleada * 20 }),
  dm:     (r) => ({ exp: 400 + r.bajas * 10 }),
  bomba:  (r) => ({ exp: 350 + r.bajas * 10 }),
  atraco: (r) => ({ exp: 500 }),
  libre:  (_) => ({ exp: 0 }),
};

// ---------------------------------------------------------------------------
// LAS MONEDAS DE JUGAR: POCAS, Y MAS PARA QUIEN HACE COSAS.
//
// Lo pidio asi el usuario: se gana poco jugando; mas si eres MVP, con mas bajas, mas daño y haciendo
// el objetivo; si haces las tres cosas ganas bien, pero no tanto como para que no merezca la pena
// recargar. El que pierde cobra lo mismo pero a la MITAD.
//
// Referencia de lo que sale (ganando):
//   jugar sin hacer nada ................ 30
//   5 bajas, 800 de daño ................ 61
//   MVP con 12 bajas, 2.000 de daño y 1 objetivo ... 30+36+40+25 = 131, +20 % = 157, +40 = 197
//   lo maximo (todo al tope y MVP) ...... 256 (y TOPE 260 por si se toca algun numero)
// Y el mazo chupetin cuesta 1.200: unas 6 partidas muy buenas o 20 normales.
//
// OJO: bajas, daño, objetivos y MVP los cuenta el juego. Los topes de aqui son lo que acota a quien
// mande numeros inventados: por mucho que diga, una partida no paga mas de TOPE.
// La MISMA cuenta vive en `Settings.monedas_de_partida` (el juego sin cuenta): si cambia una, la otra.
// ---------------------------------------------------------------------------
const MONEDAS = {
  BASE: 30,               // por jugar la partida entera
  POR_BAJA: 3, BAJAS_TOPE: 20,
  DANO_POR_MONEDA: 50, DANO_TOPE: 40,       // 1 moneda cada 50 de daño, hasta 40
  POR_OBJETIVO: 25, OBJETIVOS_TOPE: 2,      // plantar/desactivar la C4, ingresar un cubo, tumbar al jefe
  MVP_EXTRA: 0.20,        // el MVP cobra un 20 % mas de todo lo anterior...
  MVP_TRIPLE: 40,         // ...y si ademas hizo las tres cosas (bajas, daño y objetivo), esto encima
  TRIPLE_DANO_MIN: 500,
  TOPE: 260,
  PERDER: 0.5,            // el que pierde: lo mismo, a la mitad
  // EL 10 % (2026-09-29, pedido: "reduce el 90 % de las ganancias: se va a ganar muy, muy poco jugando"). El oro de
  // verdad sale ahora del PASE DE BATALLA. La misma cuenta que MONEDAS_FACTOR en settings.gd.
  FACTOR: 0.10,
};
function monedasDePartida(r, gano) {
  const bajas = Math.min(MONEDAS.BAJAS_TOPE, r.bajas) * MONEDAS.POR_BAJA;
  const dano = Math.min(MONEDAS.DANO_TOPE, Math.floor(r.dano / MONEDAS.DANO_POR_MONEDA));
  const obj = Math.min(MONEDAS.OBJETIVOS_TOPE, r.objetivos) * MONEDAS.POR_OBJETIVO;
  let total = MONEDAS.BASE + bajas + dano + obj;
  let mvp = 0, triple = false;
  if (r.mvp) {
    mvp = Math.floor(total * MONEDAS.MVP_EXTRA);
    triple = r.bajas > 0 && r.dano >= MONEDAS.TRIPLE_DANO_MIN && r.objetivos > 0;
    if (triple) mvp += MONEDAS.MVP_TRIPLE;
  }
  total = Math.min(MONEDAS.TOPE, total + mvp);
  if (!gano) total = Math.floor(total * MONEDAS.PERDER);
  total = Math.floor(total * ajJuego('oro_partida', MONEDAS.FACTOR));
  return { oro: total, detalle: { base: MONEDAS.BASE, bajas, dano, objetivo: obj, mvp, triple, perdio: !gano } };
}
// ---------------------------------------------------------------------------
// LA EXPERIENCIA SALE DE LOS LOGROS (2026-09-28). En los modos por equipos el juego manda lo que has hecho
// (doble eliminacion, nemesis, primera sangre...: godot/scripts/logros.gd) y AQUI se decide cuanto vale. Cada
// cuenta se acota con las bajas que dice la partida: no hay triple eliminacion sin tres bajas, ni mas
// "eliminacion" que bajas. La MISMA tabla vive en logros.gd (el juego sin cuenta): si cambia una, la otra.
// ---------------------------------------------------------------------------
// (2026-10-13) valores mucho mas chicos: antes casi cualquier victoria llegaba al tope de 3000. Y dos logros que solo
// gana UNO de la partida: mas_bajas y mas_dano (los decide el juego comparando con todos, bots incluidos).
const LOGROS_EXP = {
  ultra: 150, multiple: 100, bestial: 150, triple: 70, doble: 40, racha: 100, nemesis: 60,
  venganza: 40, primera: 60, eliminacion: 25, asistencia: 10, mas_bajas: 200, mas_dano: 200,
  victoria: 300, mvp: 250, partida: 100,
};
function logrosValidos(b, datos, gano) {
  const l = (b && typeof b === 'object') ? b : {};
  const n = (k) => Math.max(0, parseInt(l[k] || 0, 10) || 0);
  const bj = datos.bajas;
  const v = {
    eliminacion: Math.min(n('eliminacion'), bj),
    doble: Math.min(n('doble'), Math.floor(bj / 2)),
    triple: Math.min(n('triple'), Math.floor(bj / 3)),
    multiple: Math.min(n('multiple'), Math.floor(bj / 4)),
    ultra: Math.min(n('ultra'), Math.floor(bj / 5)),
    racha: Math.min(n('racha'), Math.floor(bj / 5)),
    bestial: Math.min(n('bestial'), Math.floor(bj / 8)),
    nemesis: Math.min(n('nemesis'), bj),
    venganza: Math.min(n('venganza'), bj),
    primera: Math.min(n('primera'), 1),
    asistencia: Math.min(n('asistencia'), 60),
    mas_bajas: bj > 0 ? Math.min(n('mas_bajas'), 1) : 0,
    mas_dano: Math.min(n('mas_dano'), 1),
    victoria: gano ? 1 : 0,
    mvp: datos.mvp ? 1 : 0,
    partida: 1,
  };
  const detalle = {};
  let exp = 0;
  for (const k of Object.keys(v)) {
    if (v[k] > 0) { detalle[k] = { veces: v[k], exp: v[k] * LOGROS_EXP[k] }; exp += detalle[k].exp; }
  }
  return { exp, detalle };
}
/** Topes duros: ningun modo puede pagar mas que esto por partida, pase lo que pase. */
const TOPE_EXP = 3000;
const TOPE_ORO = MONEDAS.TOPE;
/** Una partida de tres segundos no paga: es el freno contra el bucle de "entrar y salir". */
const SEGUNDOS_MINIMOS = 60;
/** Y no mas de esto por hora y cuenta. */
const PARTIDAS_POR_HORA = 20;

// ---------------------------------------------------------------------------
// Almacenamiento: GCS por REST, o carpeta local si BREACH_LOCAL
//
// Se devuelve SIEMPRE la "generacion" del objeto junto al contenido, porque es lo que permite
// escribir con `ifGenerationMatch` y no pisarse cuando el mismo jugador juega desde dos sitios.
// ---------------------------------------------------------------------------
let tokenGcs = { valor: '', caduca: 0 };

async function tokenMetadatos() {
  if (tokenGcs.valor && Date.now() < tokenGcs.caduca) return tokenGcs.valor;
  const r = await fetch(
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token',
    { headers: { 'Metadata-Flavor': 'Google' } });
  if (!r.ok) throw new Error('metadatos ' + r.status);
  const j = await r.json();
  tokenGcs = { valor: j.access_token, caduca: Date.now() + (j.expires_in - 60) * 1000 };
  return tokenGcs.valor;
}

function rutaLocal(nombre) { return path.join(LOCAL, nombre.replace(/\//g, '_')); }

/** Lee un objeto. Devuelve {datos, generacion} o null si no existe. */
async function leer(nombre) {
  if (LOCAL) {
    try {
      const txt = fs.readFileSync(rutaLocal(nombre), 'utf8');
      const st = fs.statSync(rutaLocal(nombre));
      return { datos: JSON.parse(txt), generacion: String(st.mtimeMs) };
    } catch { return null; }
  }
  const tk = await tokenMetadatos();
  const url = `https://storage.googleapis.com/storage/v1/b/${BUCKET}/o/${encodeURIComponent(nombre)}?alt=media`;
  const r = await fetch(url, { headers: { Authorization: 'Bearer ' + tk } });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error('gcs leer ' + r.status);
  const gen = r.headers.get('x-goog-generation') || '';
  return { datos: await r.json(), generacion: gen };
}

/**
 * Escribe un objeto con precondicion.
 *   generacion === '0'  -> solo si NO existe (es asi como se registra sin condicion de carrera)
 *   generacion === null -> sin precondicion
 *   otra                -> solo si sigue en esa generacion
 * Devuelve la generacion nueva, o null si la precondicion fallo (hay que reintentar).
 */
async function escribir(nombre, datos, generacion) {
  if (LOCAL) {
    fs.mkdirSync(LOCAL, { recursive: true });
    const p = rutaLocal(nombre);
    if (generacion === '0' && fs.existsSync(p)) return null;
    fs.writeFileSync(p, JSON.stringify(datos, null, 2));
    return String(fs.statSync(p).mtimeMs);
  }
  const tk = await tokenMetadatos();
  let url = `https://storage.googleapis.com/upload/storage/v1/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(nombre)}`;
  if (generacion !== null) url += `&ifGenerationMatch=${generacion}`;
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + tk, 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  });
  if (r.status === 412 || r.status === 409) return null;   // la precondicion fallo
  if (!r.ok) throw new Error('gcs escribir ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const j = await r.json();
  return String(j.generation || '');
}

/** Borra un objeto (no pasa nada si no existe). */
async function borrarObjeto(nombre) {
  if (LOCAL) { try { fs.unlinkSync(rutaLocal(nombre)); } catch {} return; }
  const tk = await tokenMetadatos();
  const r = await fetch(`https://storage.googleapis.com/storage/v1/b/${BUCKET}/o/${encodeURIComponent(nombre)}`,
    { method: 'DELETE', headers: { Authorization: 'Bearer ' + tk } });
  if (!r.ok && r.status !== 404) throw new Error('gcs borrar ' + r.status);
}

/**
 * Los objetos que empiezan por `prefijo` ("cuentas/"), para el panel de administracion: [{nombre, t}], con el nombre
 * sin el prefijo ni el ".json" y `t` la ultima vez que se escribio. En GCS listar es una operacion de clase A (1 por
 * cada 1.000 objetos): solo lo usa el panel, y con cache.
 */
async function listar(prefijo) {
  const quitar = (n) => n.slice(prefijo.length).replace(/\.json$/, '');
  if (LOCAL) {
    const pl = prefijo.replace(/\//g, '_');
    let fich = [];
    try { fich = fs.readdirSync(LOCAL).filter((f) => f.startsWith(pl) && f.endsWith('.json')); } catch {}
    return fich.map((f) => ({ nombre: f.slice(pl.length).replace(/\.json$/, ''), t: fs.statSync(path.join(LOCAL, f)).mtimeMs }));
  }
  const tk = await tokenMetadatos();
  const out = [];
  let pagina = '';
  for (let i = 0; i < 20; i++) {
    let u = `https://storage.googleapis.com/storage/v1/b/${BUCKET}/o?prefix=${encodeURIComponent(prefijo)}&maxResults=1000&fields=items(name,updated),nextPageToken`;
    if (pagina) u += '&pageToken=' + encodeURIComponent(pagina);
    const r = await fetch(u, { headers: { Authorization: 'Bearer ' + tk } });
    if (!r.ok) throw new Error('gcs listar ' + r.status);
    const j = await r.json();
    for (const it of j.items || []) out.push({ nombre: quitar(it.name), t: Date.parse(it.updated) || 0 });
    pagina = j.nextPageToken || '';
    if (!pagina) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Caché en memoria. Las lecturas de GCS son el segundo recurso escaso (50.000/mes gratis) y mirar el
// perfil dos veces seguidas no tiene por que bajar el objeto otra vez.
// ---------------------------------------------------------------------------
const cache = new Map();
function deCache(k) {
  const e = cache.get(k);
  if (!e || Date.now() > e.hasta) { cache.delete(k); return null; }
  return e;
}
function borrarCache(k) { cache.delete(k); }
function aCache(k, datos, generacion) {
  if (cache.size > 5000) cache.clear();               // tope de memoria: 512 MiB no son infinitos
  cache.set(k, { datos, generacion, hasta: Date.now() + CACHE_MS });
}

// ---------------------------------------------------------------------------
// Claves y tokens
//
// scrypt es deliberadamente LENTO (ahi esta la gracia: encarece probar millones de claves). Por eso
// solo se paga al registrarse y al entrar; a partir de ahi se usa un token firmado y validarlo no
// cuesta ni una lectura del bucket.
// ---------------------------------------------------------------------------
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 32 };

function hashClave(clave, sal) {
  return crypto.scryptSync(clave, sal, SCRYPT.keylen, { N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p }).toString('hex');
}
function igualesEnTiempoFijo(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);   // comparar con === filtra la clave por el tiempo que tarda
}
function b64u(b) { return Buffer.from(b).toString('base64url'); }

function firmarToken(usuario) {
  const cuerpo = b64u(JSON.stringify({ u: usuario, c: Date.now() + DIAS_TOKEN * 86400000 }));
  const firma = crypto.createHmac('sha256', SECRETO).update(cuerpo).digest('base64url');
  return cuerpo + '.' + firma;
}
function leerToken(tok) {
  if (typeof tok !== 'string' || !tok.includes('.')) return null;
  const [cuerpo, firma] = tok.split('.');
  const esperada = crypto.createHmac('sha256', SECRETO).update(cuerpo).digest('base64url');
  if (!igualesEnTiempoFijo(firma, esperada)) return null;
  try {
    const d = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
    if (!d.u || Date.now() > d.c) return null;
    return d.u;
  } catch { return null; }
}

// ---------------------------------------------------------------------------
// Validacion
//
// El nombre de usuario ES el nombre del fichero, asi que se filtra a conciencia: sin barras, sin
// puntos y con longitud acotada. Un nombre como "../otro" no puede existir.
// ---------------------------------------------------------------------------
function normalizarUsuario(u) {
  if (typeof u !== 'string') return '';
  const s = u.trim().toLowerCase();
  if (!/^[a-z0-9_-]{3,16}$/.test(s)) return '';
  // "g_" queda RESERVADO para las cuentas de Google (`usuarioDeGoogle`). Sin esto, alguien podria
  // registrar a mano el usuario que le corresponderia a una cuenta de Google y quedarse con ella.
  if (s.startsWith('g_')) return '';
  return s;
}
function claveValida(c) { return typeof c === 'string' && c.length >= 6 && c.length <= 72; }
function objetoDe(usuario) { return `cuentas/${usuario}.json`; }

/**
 * Identidad interna de una cuenta de Google.
 *
 * El `sub` de Google son ~21 digitos y el nombre de usuario ES el nombre del fichero (3-16
 * caracteres), asi que no cabe. Se usa un hash corto con prefijo `g_`, que ademas deja claro de un
 * vistazo que esa cuenta es de Google y no puede chocar con un usuario escrito a mano (los normales
 * no pueden empezar por "g_" porque se reserva abajo).
 */
function usuarioDeGoogle(sub) {
  return 'g_' + crypto.createHash('sha256').update('google:' + sub).digest('hex').slice(0, 14);
}

/**
 * NOMBRE PUBLICO DEL JUGADOR. Es el que se ve en la partida, y tiene que ser UNICO.
 *
 * No vale con mirar si existe y luego escribirlo: entre las dos cosas cabe otro jugador pidiendo el
 * mismo nombre, y acabarian los dos con el. Se reserva igual que se registra una cuenta: creando un
 * objeto `nombres/<nombre>.json` con `ifGenerationMatch=0`, que falla si ya existe. El propio
 * almacenamiento hace de arbitro y la carrera no puede darse.
 */
function normalizarNombre(n) {
  if (typeof n !== 'string') return '';
  const s = n.trim();
  // se permiten mayusculas y tildes en lo que se VE, pero la reserva va en minusculas y sin acentos:
  // si no, "Pepe" y "pepe" serian dos jugadores distintos y nadie los distinguiria en una partida
  if (!/^[\p{L}0-9 _-]{3,16}$/u.test(s)) return '';
  if (/^\s|\s$|\s\s/.test(s)) return '';
  return s;
}
function claveNombre(n) {
  return 'nombres/' + n.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, '_') + '.json';
}

/** Intenta quedarse con el nombre. Devuelve true si era libre. */
async function reservarNombre(nombre, usuario) {
  const gen = await escribir(claveNombre(nombre), { usuario, nombre, desde: new Date().toISOString() }, '0');
  if (gen !== null) return true;
  // ya existe: solo vale si el duenyo soy yo (rehacer la misma reserva no puede fallar)
  const act = await leer(claveNombre(nombre));
  return !!(act && act.datos && act.datos.usuario === usuario);
}

async function soltarNombre(nombre) {
  if (!nombre) return;
  if (LOCAL) { try { fs.unlinkSync(rutaLocal(claveNombre(nombre))); } catch {} return; }
  try {
    const tk = await tokenMetadatos();
    await fetch(`https://storage.googleapis.com/storage/v1/b/${BUCKET}/o/${encodeURIComponent(claveNombre(nombre))}`,
      { method: 'DELETE', headers: { Authorization: 'Bearer ' + tk } });
  } catch {}
}

function perfilPublico(c) {
  return {
    usuario: c.usuario, nombre: c.nombre, exp: c.exp, monedas: c.monedas,
    // CREDITOS: la moneda que se recarga con dinero real (packs de la tienda). Aparte de las monedas
    // que se ganan jugando. Solo los suma el servidor, cuando el pago esta aprobado.
    creditos: c.creditos || 0,
    misiones: misionesPublicas(c, Date.now()),
    equipo: c.equipo || null,
    // el juego pide el nombre antes de dejar entrar al lobby si esto es false
    nombre_elegido: c.nombre_elegido === true,
    nivel: nivelDe(c.exp), armas: c.armas || [],
    partidas: c.partidas || 0, ganadas: c.ganadas || 0,
    id_pub: c.id_pub || null,
    // LOS REGALOS DEL PANEL por reclamar (admin.js): el lobby los enseña y los pide con /regalo/reclamar
    regalos: admin ? admin.regalosPublicos(c) : [],
    // EL PASE DE BATALLA: lo reclamado de cada temporada ({t1: {g: [niveles], p: [niveles]}})
    pase: c.pase || {},
    // la EXP del pase de esta temporada (aparte de exp: solo de las tareas)
    pase_exp: expPase(c),
    // EL CAMINO DEL PROGRESO: los niveles ya dados (camino_progreso.gd; /camino/reclamar)
    camino: c.camino || [],
    // CUBOS DE FUERZA, los COFRES por abrir (la rareza con la que empieza cada uno) y el NIVEL de cada personaje
    cubos: c.cubos || 0, cofres: c.cofres || [], personajes: c.personajes || {},
    // LAS CARTAS (scripts/cartas.gd): id -> {n: nivel, c: copias juntadas para el siguiente}
    cartas: c.cartas || {},
    // LA TIENDA / DINERO: las ofertas de UNICA VEZ ya compradas y lo que falta (ms) para lo gratis (el oro y el cofre)
    packs_unicos: c.packs_unicos || [],
    gratis: { oro: gratisRestante(c, 'oro', Date.now()), cofre: gratisRestante(c, 'cofre', Date.now()) },
    // LOS ME GUSTA recibidos en las pantallas de final (reportes.js, POST /likes)
    likes: c.likes || 0,
  };
}
/** Lo que cuesta en creditos: 25 % menos, redondeado hacia arriba. La MISMA cuenta que
 * `Settings.precio_creditos()` en el juego (si cambia una, cambia la otra). */
const DESCUENTO_CREDITOS = 0.25;   // (ya no se usa: ver ORO_POR_DIAMANTE)
/** LA ECONOMIA (2026-09-30): lo que tiene precio en oro, pagado con diamantes, cuesta precio / 10 (lo mismo que cambiar
 * diamantes por oro sin rebaja). La MISMA cuenta que Settings.precio_creditos() en el juego. */
const ORO_POR_DIAMANTE = 10;

/**
 * LOS PRECIOS LOS TIENE EL SERVIDOR. Antes /compra cobraba el precio que mandaba el juego: con un proxy
 * se compraba cualquier cosa por 0. La lista sale del propio juego (`--exportarprecios`, ver lobby.gd)
 * y viaja en la imagen. Lo que no esta en la lista NO se vende. BREACH_PRECIOS permite otra lista
 * (las pruebas usan una suya).
 */
const PRECIOS = (() => {
  const ruta = process.env.BREACH_PRECIOS || path.join(__dirname, 'precios.json');
  try {
    const j = JSON.parse(fs.readFileSync(ruta, 'utf8'));
    const limpio = {};
    for (const [k, v] of Object.entries(j)) {
      const n = parseInt(v, 10);
      if (typeof k === 'string' && k.length <= 48 && n > 0) limpio[k] = n;
    }
    console.log(`[precios] ${Object.keys(limpio).length} articulos a la venta`);
    return limpio;
  } catch (e) {
    console.error('[precios] no se pudo leer la lista de precios: no se vende nada', e.message);
    return {};
  }
})();
/** Nombre y tipo de cada articulo de la tienda, para el panel: {clave: {n, t}}. Lo exporta el juego junto a los precios. */
const CATALOGO = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, 'catalogo.json'), 'utf8')); } catch { return {}; }
})();
function precioConCreditos(precio) { return Math.ceil(precio / ORO_POR_DIAMANTE); }

/**
 * EL PASE DE BATALLA (2026-09-29). La tabla la exporta el juego (`--exportarprecios` -> pase.json, desde
 * scripts/pase_batalla.gd) y viaja en la imagen: que da cada nivel en la fila gratis ("g") y en la premium ("p").
 * Va con el NIVEL DE LA CUENTA (nivelDe). Lo reclamado se apunta en la cuenta: `pase.t<temporada>.g|p` = [niveles].
 * La premium se abre comprando `clave_premium` (en diamantes, a precio entero: ver /compra).
 */
const PASE = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, 'pase.json'), 'utf8')); } catch { return null; }
})();
/** Da una cosa del pase a la cuenta (dentro de actualizar). Devuelve el texto de lo dado. */
function darDelPase(cu, c) {
  const v = c.v;
  switch (c.t) {
    case 'oro': cu.monedas = (cu.monedas || 0) + (parseInt(v, 10) || 0); return `${v} oro`;
    case 'diamantes': cu.creditos = (cu.creditos || 0) + (parseInt(v, 10) || 0); return `${v} diamantes`;
    case 'cubos': cu.cubos = (cu.cubos || 0) + (parseInt(v, 10) || 0); return `${v} cubos`;
    case 'cofre': cu.cofres = (cu.cofres || []).concat([Math.max(0, Math.min(5, parseInt(v, 10) || 0))]).slice(-50); return 'cofre';
    case 'habilidad': return meter(cu, 'hab_' + String(v));
    case 'modelo': return meter(cu, 'modelo:' + String(v));
    case 'pintura': case 'mazo': return meter(cu, String(v));
    default: return '';
  }
}
/**
 * LOS COFRES Y EL NIVEL DE LOS PERSONAJES (2026-09-29). Las tablas las exporta el juego (`--exportarprecios` ->
 * progreso.json, desde scripts/cofres.gd y scripts/nivel_personaje.gd). El cofre se sortea AQUI (crypto) y el juego solo
 * anima lo que le decimos: `etapas` es la rareza despues de cada toque.
 */
const PROGRESO = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, 'progreso.json'), 'utf8')); } catch { return null; }
})();
function azar() { return crypto.randomInt(0, 1000000) / 1000000; }
function entre(a, b) { return a + crypto.randomInt(0, Math.max(1, b - a + 1)); }
function sortearCofre(cu, inicio) {
  const t = { ...PROGRESO.cofres, sube: ajJuego('cofres_sube', PROGRESO.cofres.sube), premios: ajJuego('cofres_premios', PROGRESO.cofres.premios) };
  let r = Math.max(0, Math.min(5, inicio));
  const etapas = [];
  for (let i = 0; i < t.toques; i++) {
    if (r < 5 && azar() < t.sube[r]) r++;
    etapas.push(r);
  }
  // UNA opcion por su peso (w); casi siempre CARTAS (ver scripts/cofres.gd)
  const opciones = t.premios[r];
  const total = opciones.reduce((a, x) => a + (x.w || 1), 0);
  let tiro = crypto.randomInt(0, Math.max(1, total));
  let o = opciones[0];
  for (const x of opciones) { tiro -= (x.w || 1); if (tiro < 0) { o = x; break; } }
  let premio;
  if (o.t === 'carta') {
    const tc = t.cartas || { ids: [], rareza: {}, nivel_max: 10 };
    const nivelDeCarta = (id) => ((cu.cartas || {})[id] || {}).n || 0;
    const libres = tc.ids.filter((id) => (tc.rareza[id] || 0) <= o.hasta && nivelDeCarta(id) < tc.nivel_max);
    if (libres.length) {
      const id = libres[crypto.randomInt(0, libres.length)];
      premio = { t: 'carta', v: id, n: entre(o.min, o.max), nueva: nivelDeCarta(id) <= 0 };
    } else o = o.si_no;
  }
  if (!premio && o.t === 'articulo') {
    const tiene = new Set(cu.armas || []);
    const libres = o.pool.filter((k) => !tiene.has(k));
    if (libres.length) premio = { t: 'articulo', v: libres[crypto.randomInt(0, libres.length)] };
    else o = o.si_no;
  }
  if (!premio) premio = { t: o.t, v: entre(o.min, o.max) };
  return { inicio, etapas, rareza: r, premio };
}
function darPremioCofre(cu, p) {
  if (p.t === 'oro') cu.monedas = (cu.monedas || 0) + p.v;
  else if (p.t === 'cubos') cu.cubos = (cu.cubos || 0) + p.v;
  else if (p.t === 'diamantes') cu.creditos = (cu.creditos || 0) + p.v;
  else if (p.t === 'articulo') meter(cu, p.v);
  else if (p.t === 'carta') darCarta(cu, p.v, p.n || 1);
}
/** Copias de una carta: la primera la da a nivel 1; las demas se juntan para mejorarla (/carta/mejorar). */
/**
 * EL CAMINO DEL PROGRESO (2026-10-04). La tabla la exporta el juego (`--exportarprecios` -> camino.json, desde
 * scripts/camino_progreso.gd): lo que se desbloquea en cada nivel de la cuenta, sin comprarlo. Lo alcanzado se da SOLO
 * (el juego llama a /camino/reclamar al montar el vestibulo): aqui se valida el nivel y se apunta en `camino`. Lo que ya
 * se tenia (un arma o un personaje comprado antes) da su `si_ya` en oro.
 */
const CAMINO = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, 'camino.json'), 'utf8')); } catch { return null; }
})();
function darDelCamino(cu, c) {
  const v = c.v;
  switch (c.t) {
    case 'arma': {
      if ((cu.armas || []).includes(String(v))) { cu.monedas = (cu.monedas || 0) + (parseInt(c.si_ya, 10) || 0); return `${c.si_ya || 0} oro (ya tenia ${v})`; }
      return meter(cu, String(v));
    }
    case 'modelo': {
      if ((cu.armas || []).includes('modelo:' + String(v))) { cu.monedas = (cu.monedas || 0) + (parseInt(c.si_ya, 10) || 0); return `${c.si_ya || 0} oro (ya tenia ${v})`; }
      return meter(cu, 'modelo:' + String(v));
    }
    case 'carta': darCarta(cu, String(v), Math.max(1, parseInt(c.n, 10) || 1)); return `${c.n || 1} carta ${v}`;
    case 'pintura': case 'mazo': {
      if ((cu.armas || []).includes(String(v))) { cu.monedas = (cu.monedas || 0) + (parseInt(c.si_ya, 10) || 0); return `${c.si_ya || 0} oro (ya tenia ${v})`; }
      return meter(cu, String(v));
    }
    default: return darDelPase(cu, c);
  }
}
function darCarta(cu, id, k) {
  cu.cartas = cu.cartas || {};
  const e = cu.cartas[id] || { n: 0, c: 0 };
  if (e.n <= 0) { e.n = 1; k -= 1; }
  e.c = (e.c || 0) + Math.max(0, k);
  cu.cartas[id] = e;
}
function meter(cu, clave) {
  cu.armas = cu.armas || [];
  if (!cu.armas.includes(clave)) cu.armas.push(clave);
  return clave;
}

/**
 * LOS AJUSTES DE LA TIENDA (2026-09-29, pedido: "que el panel pueda editar los nombres de los productos y los
 * precios"). Encima de la lista del juego (precios.json + catalogo.json, que viajan en la imagen) el panel pone
 * precios y nombres propios, que se guardan en el bucket (`admin/tienda.json`) y se cargan al arrancar (el servidor es
 * UNA instancia: con eso basta). Lo que se vende sigue siendo lo de precios.json: el panel cambia el precio, no añade
 * articulos. El juego los pide con GET /tienda y el latido le dice cuando cambian (`tv`).
 */
let TIENDA = { v: 0, precios: {}, nombres: {}, destacados: [], juego: {}, packs: {} };
async function cargarTienda() {
  try {
    const e = await leer('admin/tienda.json');
    if (e && e.datos) {
      TIENDA = { v: Number(e.datos.v) || 0, precios: e.datos.precios || {}, nombres: e.datos.nombres || {},
        destacados: Array.isArray(e.datos.destacados) ? e.datos.destacados : [], juego: e.datos.juego || {}, packs: e.datos.packs || {} };
      console.log(`[tienda] ${Object.keys(TIENDA.precios).length} precios y ${Object.keys(TIENDA.nombres).length} nombres del panel`);
    }
  } catch (err) { console.error('[tienda] no se pudieron leer los ajustes', err.message); }
}
async function guardarTienda(parcial) {
  // lo que no se manda se queda como estaba (precios y nombres, destacados, juego)
  const nueva = { ...TIENDA, ...parcial };
  nueva.v = (TIENDA.v || 0) + 1;
  await escribir('admin/tienda.json', nueva, null);
  TIENDA = nueva;
}
/** Lo que cuesta de verdad: el precio del panel si lo hay, si no el de la lista del juego. */
function precioDe(clave) {
  if (clave === clavePremium()) return parseInt(paseCfg().precio, 10) || PRECIOS.pase_t1 || 950;
  const p = Number(TIENDA.precios[clave]);
  return p > 0 ? p : PRECIOS[clave];
}
function nombreDe(clave) {
  return TIENDA.nombres[clave] || (CATALOGO[clave] && CATALOGO[clave].n) || clave;
}

/**
 * LOS AJUSTES DEL JUEGO (2026-09-30, pedido: "que el panel pueda modificar la probabilidad de que te toque comun,
 * especial, etc.; agregar destacados con precios en la tienda; modificar todo el juego; la cantidad de cartas que te da
 * el cofre"). Van en el mismo `admin/tienda.json` (`juego` y `destacados`) y viajan al juego con GET /tienda. Lo que no
 * este en `juego` es lo de fabrica (las tablas que exporta el juego: progreso.json, pase.json, MONEDAS).
 *   cofres_sube        [5]  probabilidad de SUBIR de rareza en cada toque (0 comun .. 4 legendaria)
 *   cofres_premios     [6]  por rareza, las opciones con su peso: {t, w, min, max, hasta (carta), pool (articulo), si_no}
 *   cartas_copias      [10] copias para pasar del nivel n al n+1
 *   cartas_oro         [10] oro para pasar del nivel n al n+1
 *   cartas_cubos       [10] cubos de fuerza para pasar del nivel n al n+1 (nunca diamantes)
 *   cartas_valores     {id: {base, paso}} lo que da cada carta (solo el juego)
 *   personajes_coste   {"2": [cubos, oro], ... "11": [...]}
 *   oro_partida        el factor del oro de cada partida (0,10 = el 10 %)
 *   pase_niveles       [{nivel, g: [{t, v}], p: [{t, v}]}] lo que da cada nivel del pase
 *   destacados_diarios si siguen saliendo las pinturas del dia en DESTACADAS (ademas de las del panel)
 * `destacados`: [{clave, precio, moneda ("monedas" | "creditos")}], hasta 8: se cobran a ESE precio y en ESA moneda.
 */
/** Cubos de fuerza por mejora de carta si progreso.json aun no los trae (lo mismo que cartas.gd CUBOS_MEJORA) */
const CARTAS_CUBOS_FABRICA = [0, 1, 1, 2, 3, 4, 6, 8, 12, 16];
function ajJuego(k, def) {
  const j = TIENDA.juego || {};
  return j[k] !== undefined && j[k] !== null ? j[k] : def;
}
function juegoFabrica() {
  const pc = (PROGRESO && PROGRESO.cofres) || {};
  const tc = pc.cartas || {};
  return {
    cofres_sube: pc.sube || [], cofres_premios: pc.premios || [],
    cartas_copias: tc.copias || [], cartas_oro: tc.oro || [], cartas_cubos: tc.cubos || CARTAS_CUBOS_FABRICA,
    cartas_valores: tc.valores || {},
    personajes_coste: (PROGRESO && PROGRESO.personajes && PROGRESO.personajes.coste) || {},
    oro_partida: MONEDAS.FACTOR, pase_niveles: (PASE && PASE.niveles) || [], destacados_diarios: true,
    // LA VERSION DE LA APP (2026-10-01): {ultima, minima, url, mensaje}. El juego compara su numero (Settings.VERSION_APP,
    // el version code del APK) y si es menor que `ultima` avisa de que hay una nueva; si es menor que `minima`, obliga.
    // 0 = sin aviso. Se cambia desde el panel (pestana VERSION) sin volver a desplegar.
    version_app: { ultima: 0, minima: 0, url: '', mensaje: '' },
    // LOS BLOQUEOS (2026-10-03, pedido: "bloquear un mapa, un modo, un personaje o un articulo mientras arreglo un bug"):
    // listas de ids. El juego no enseña ni deja usar lo bloqueado (TiendaAjustes.bloqueado) y aqui no se cobra (/compra).
    // De fabrica, NUKE (sin terminar).
    bloqueos: { mapas: ['nuke'], modos: [], personajes: [], articulos: [] },
    // EL PASE DESDE EL PANEL (2026-10-17, pedido: "activarlo y desactivarlo, y hacer la temporada 2"): apagado, el juego
    // esconde su tarjeta y las tareas y aqui no se reclama. La temporada nueva empieza de cero sola (lo reclamado y la EXP
    // van por temporada: cu.pase.t<n>, cu.pase_exp.t<n>) y su premium es otra compra (pase_t<n>, a `precio` diamantes).
    pase_config: { activo: true, temporada: (PASE && PASE.temporada) || 1, nombre: 'TEMPORADA ' + ((PASE && PASE.temporada) || 1),
      fin: '2026-12-31', precio: PRECIOS.pase_t1 || 950 },
  };
}
/** El pase tal como lo dejo el panel: {activo, temporada, nombre, fin, precio} */
function paseCfg() { return ajJuego('pase_config', juegoFabrica().pase_config); }
function temporadaPase() { return parseInt(paseCfg().temporada, 10) || 1; }
function clavePremium() { return 'pase_t' + temporadaPase(); }
/** ¿Esta bloqueado desde el panel? (tipo: mapas | modos | personajes | articulos) */
function bloqueado(tipo, id) {
  const b = ajJuego('bloqueos', juegoFabrica().bloqueos) || {};
  return Array.isArray(b[tipo]) && b[tipo].includes(String(id));
}
function _entero(x, a, b) { const n = Number(x); return Number.isInteger(n) && n >= a && n <= b ? n : null; }
function _numero(x, a, b) { const n = Number(x); return Number.isFinite(n) && n >= a && n <= b ? n : null; }
function _cantidad(o, tipos) {
  if (!o || !tipos.includes(o.t)) return null;
  const min = _entero(o.min, 0, 1000000), max = _entero(o.max, 0, 1000000);
  if (min === null || max === null || min > max) return null;
  return { t: o.t, min, max };
}
const _PREMIO_PASE = ['oro', 'diamantes', 'cubos', 'cofre', 'modelo', 'pintura', 'mazo', 'habilidad'];
/** Valida un ajuste del juego que manda el panel: {valor} o {error} */
function validarJuego(clave, v) {
  const fab = juegoFabrica();
  switch (clave) {
    case 'cofres_sube': {
      if (!Array.isArray(v) || v.length !== 5) return { error: 'hacen falta 5 probabilidades (comun .. legendaria)' };
      const out = v.map((x) => _numero(x, 0, 1));
      if (out.includes(null)) return { error: 'cada probabilidad va de 0 a 1' };
      return { valor: out };
    }
    case 'cofres_premios': {
      if (!Array.isArray(v) || v.length !== 6) return { error: 'hacen falta las 6 rarezas' };
      const out = [];
      for (let r = 0; r < 6; r++) {
        const ops = v[r];
        if (!Array.isArray(ops) || !ops.length || ops.length > 8) return { error: `rareza ${r}: de 1 a 8 opciones` };
        const lista = [];
        for (const o of ops) {
          const w = _entero(o && o.w, 0, 1000);
          if (w === null) return { error: `rareza ${r}: el peso va de 0 a 1000` };
          if (o.t === 'articulo') {
            const pool = Array.isArray(o.pool) ? o.pool.map(String).filter((k) => Object.prototype.hasOwnProperty.call(PRECIOS, k)) : [];
            if (!pool.length || pool.length > 40) return { error: `rareza ${r}: el articulo necesita de 1 a 40 articulos que existan` };
            const si = _cantidad(o.si_no, ['oro', 'cubos', 'diamantes']);
            if (!si) return { error: `rareza ${r}: falta lo que da si ya tienes todos los articulos` };
            lista.push({ t: 'articulo', w, pool, si_no: si });
            continue;
          }
          const c = _cantidad(o, ['carta', 'oro', 'cubos', 'diamantes']);
          if (!c) return { error: `rareza ${r}: tipo o cantidades no validos (min <= max)` };
          const x = { ...c, w };
          if (o.t === 'carta') {
            const h = _entero(o.hasta, 0, 5);
            const si = _cantidad(o.si_no, ['oro', 'cubos', 'diamantes']);
            if (h === null || !si) return { error: `rareza ${r}: la carta necesita "hasta" (0-5) y lo que da si no quedan cartas` };
            x.hasta = h; x.si_no = si;
          }
          lista.push(x);
        }
        if (!lista.some((x) => x.w > 0)) return { error: `rareza ${r}: alguna opcion tiene que tener peso` };
        out.push(lista);
      }
      return { valor: out };
    }
    case 'cartas_copias': case 'cartas_oro': case 'cartas_cubos': {
      const n = (fab[clave] || []).length || 10;
      if (!Array.isArray(v) || v.length !== n) return { error: `hacen falta ${n} valores (uno por nivel)` };
      const out = v.map((x) => _entero(x, 0, 10000000));
      if (out.includes(null)) return { error: 'cada valor es un entero de 0 a 10.000.000' };
      out[0] = 0;
      return { valor: out };
    }
    case 'cartas_valores': {
      if (!v || typeof v !== 'object') return { error: 'no valido' };
      const out = {};
      for (const id of Object.keys(fab.cartas_valores || {})) {
        const x = v[id] || fab.cartas_valores[id];
        const base = _numero(x.base, 0, 100), paso = _numero(x.paso, 0, 100);
        if (base === null || paso === null) return { error: `${id}: base y paso de 0 a 100` };
        out[id] = { base, paso };
      }
      return { valor: out };
    }
    case 'personajes_coste': {
      if (!v || typeof v !== 'object') return { error: 'no valido' };
      const out = {};
      for (const k of Object.keys(fab.personajes_coste)) {
        const x = v[k];
        const cu = _entero(x && x[0], 0, 1000000), oro = _entero(x && x[1], 0, 10000000);
        if (cu === null || oro === null) return { error: `nivel ${k}: cubos y oro enteros` };
        out[k] = [cu, oro];
      }
      return { valor: out };
    }
    case 'oro_partida': {
      const f = _numero(v, 0, 10);
      if (f === null) return { error: 'el factor va de 0 a 10 (0,10 = el 10 %)' };
      return { valor: f };
    }
    case 'destacados_diarios':
      return { valor: !!v };
    case 'version_app': {
      if (!v || typeof v !== 'object') return { error: 'no valido' };
      const ultima = _entero(v.ultima, 0, 2100000000);
      if (ultima === null) return { error: 'la ultima version es un numero entero (el version code del APK)' };
      const minima = _entero(v.minima === undefined ? 0 : v.minima, 0, 2100000000);
      if (minima === null || minima > ultima) return { error: 'la version obligatoria no puede ser mayor que la ultima' };
      const url = String(v.url || '').trim().slice(0, 400);
      if (url && !/^(https?:\/\/|market:\/\/)/i.test(url)) return { error: 'el enlace tiene que empezar por https:// o market://' };
      const mensaje = String(v.mensaje || '').trim().slice(0, 300);
      return { valor: { ultima, minima, url, mensaje } };
    }
    case 'bloqueos': {
      if (!v || typeof v !== 'object') return { error: 'no valido' };
      const out = {};
      for (const tipo of ['mapas', 'modos', 'personajes', 'articulos']) {
        const l = v[tipo] === undefined ? [] : v[tipo];
        if (!Array.isArray(l) || l.length > 300) return { error: `${tipo}: una lista de hasta 300` };
        const ids = [...new Set(l.map((x) => String(x).trim().slice(0, 64)).filter((x) => /^[\w:.\- ÁÉÍÓÚÑáéíóúñü]{1,64}$/.test(x)))];
        out[tipo] = ids;
      }
      return { valor: out };
    }
    case 'pase_config': {
      if (!v || typeof v !== 'object') return { error: 'no valido' };
      const temporada = _entero(v.temporada, 1, 999);
      const precio = _entero(v.precio, 1, 1000000);
      if (temporada === null) return { error: 'la temporada es un numero de 1 a 999' };
      if (precio === null) return { error: 'el precio del premium es un numero de diamantes' };
      const nombre = String(v.nombre || ('TEMPORADA ' + temporada)).trim().slice(0, 40);
      const fin = String(v.fin || '').trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(fin)) return { error: 'el fin es una fecha AAAA-MM-DD' };
      return { valor: { activo: v.activo !== false, temporada, nombre, fin, precio } };
    }
    case 'pase_niveles': {
      const fabN = fab.pase_niveles;
      if (!Array.isArray(v) || v.length !== fabN.length) return { error: `hacen falta los ${fabN.length} niveles` };
      const item = (x) => {
        if (!x || !_PREMIO_PASE.includes(x.t)) return null;
        if (['oro', 'diamantes', 'cubos'].includes(x.t)) { const n = _entero(x.v, 1, 1000000); return n === null ? null : { t: x.t, v: n }; }
        if (x.t === 'cofre') { const n = _entero(x.v, 0, 5); return n === null ? null : { t: 'cofre', v: n }; }
        const k = String(x.v || '');
        if (x.t === 'modelo') return Object.prototype.hasOwnProperty.call(PRECIOS, 'modelo:' + k) ? { t: 'modelo', v: k } : null;
        if (x.t === 'habilidad') return /^[a-z_]{2,20}$/.test(k) ? { t: 'habilidad', v: k } : null;
        return Object.prototype.hasOwnProperty.call(PRECIOS, k) ? { t: x.t, v: k } : null;
      };
      const out = [];
      for (let i = 0; i < v.length; i++) {
        const d = v[i];
        const g = Array.isArray(d && d.g) ? d.g.slice(0, 3).map(item) : [];
        const pp = Array.isArray(d && d.p) ? d.p.slice(0, 3).map(item) : [];
        if (g.includes(null) || pp.includes(null)) return { error: `nivel ${i + 1}: hay un premio no valido` };
        out.push({ nivel: i + 1, g, p: pp });
      }
      return { valor: out };
    }
  }
  return { error: 'ese ajuste no existe' };
}
/** Valida la lista de destacados: {valor} o {error} */
function validarDestacados(lista) {
  if (!Array.isArray(lista) || lista.length > 8) return { error: 'de 0 a 8 destacados' };
  const out = [], vistos = new Set();
  for (const d of lista) {
    const clave = String((d && d.clave) || '').slice(0, 48);
    if (!Object.prototype.hasOwnProperty.call(PRECIOS, clave) || clave.startsWith('pase_')) return { error: `"${clave}" no se puede destacar` };
    if (vistos.has(clave)) return { error: `"${clave}" esta repetido` };
    const precio = _entero(d.precio, 1, 10000000);
    if (precio === null) return { error: `${clave}: el precio va de 1 a 10.000.000` };
    const moneda = d.moneda === 'creditos' ? 'creditos' : 'monedas';
    vistos.add(clave);
    out.push({ clave, precio, moneda });
  }
  return { valor: out };
}

// ---------------------------------------------------------------------------
// MISIONES DIARIAS Y SEMANALES. Las lleva el servidor: el progreso sale de lo que el juego manda al acabar
// cada partida (/partida, con los mismos topes que el premio).
// LAS TAREAS DEL PASE (2026-09-29): el premio es EXPERIENCIA (sube el nivel de la cuenta, que es el pase) y ya no se
// cobra solo: cumplida queda `hecha` y se RECLAMA (/mision/reclamar), como en la pantalla de tareas de referencia.
// Son las MISMAS para todos: se eligen de la lista con un sorteo fijo por dia o por semana. El dia y la
// semana cambian a las 00:00 de Argentina (UTC-3).
//
// `stat`: que cuenta. `modo`: solo en ese modo (vacio = cualquiera). `max`: se queda con el mejor valor
// de una partida en vez de sumar (p. ej. la oleada mas alta).
// ---------------------------------------------------------------------------
const MISIONES_DIARIAS = [
  { id: 'd_jugar', texto: 'Juega 3 partidas', stat: 'partidas', meta: 3, premio: 400 },
  { id: 'd_ganar', texto: 'Gana 2 partidas', stat: 'ganadas', meta: 2, premio: 500 },
  { id: 'd_bajas', texto: 'Consigue 25 bajas', stat: 'bajas', meta: 25, premio: 450 },
  { id: 'd_dano', texto: 'Haz 4.000 de daño', stat: 'dano', meta: 4000, premio: 450 },
  { id: 'd_objetivo', texto: 'Cumple 2 objetivos', stat: 'objetivos', meta: 2, premio: 500 },
  { id: 'd_mvp', texto: 'Sé MVP en una partida', stat: 'mvp', meta: 1, premio: 600 },
  { id: 'd_oleada', texto: 'Llega a la oleada 5 en cuarentena', stat: 'oleada', meta: 5, premio: 550, modo: 'pve', max: true },
  { id: 'd_atraco', texto: 'Ingresa un cubo en el atraco', stat: 'objetivos', meta: 1, premio: 500, modo: 'atraco' },
  { id: 'd_bomba', texto: 'Gana una partida de bomba', stat: 'ganadas', meta: 1, premio: 500, modo: 'bomba' },
];
const MISIONES_SEMANALES = [
  { id: 's_ganar', texto: 'Gana 12 partidas', stat: 'ganadas', meta: 12, premio: 2000 },
  { id: 's_bajas', texto: 'Consigue 200 bajas', stat: 'bajas', meta: 200, premio: 2000 },
  { id: 's_objetivos', texto: 'Cumple 12 objetivos', stat: 'objetivos', meta: 12, premio: 2200 },
  { id: 's_mvp', texto: 'Sé MVP 5 veces', stat: 'mvp', meta: 5, premio: 2200 },
  { id: 's_oleada', texto: 'Llega a la oleada 10 en cuarentena', stat: 'oleada', meta: 10, premio: 2500, modo: 'pve', max: true },
];
const DIARIAS_POR_DIA = 3;
const SEMANALES_POR_SEMANA = 2;
const HUSO_MS = -3 * 3600000;

function claveDia(ahora) { return new Date(ahora + HUSO_MS).toISOString().slice(0, 10); }
function claveSemana(ahora) {
  const d = new Date(ahora + HUSO_MS);
  const dia = (d.getUTCDay() + 6) % 7;                       // lunes = 0
  const lunes = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - dia));
  return 'S' + lunes.toISOString().slice(0, 10);
}
/** Cuanto falta para el siguiente cambio de dia/semana, en segundos. */
function segundosHasta(ahora, semanal) {
  const d = new Date(ahora + HUSO_MS);
  const dias = semanal ? 7 - ((d.getUTCDay() + 6) % 7) : 1;
  const siguiente = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + dias);
  return Math.max(0, Math.floor((siguiente - (ahora + HUSO_MS)) / 1000));
}
/** n misiones distintas de la lista, siempre las mismas para la misma clave. */
function elegirMisiones(lista, n, clave) {
  const orden = lista.map((m, i) => ({ m, h: crypto.createHash('sha256').update(clave + ':' + m.id).digest().readUInt32BE(0) }));
  orden.sort((a, b) => a.h - b.h);
  return orden.slice(0, n).map((x) => x.m);
}
/** El progreso guardado, al dia: si cambio el dia o la semana, empieza de cero. NO toca la cuenta. */
function estadoMisiones(cu, ahora) {
  const dia = claveDia(ahora), sem = claveSemana(ahora);
  const g = cu.misiones || {};
  return {
    dia, sem,
    d: g.dia === dia ? (g.d || {}) : {},
    s: g.sem === sem ? (g.s || {}) : {},
  };
}
function misionesPublicas(cu, ahora) {
  const st = estadoMisiones(cu, ahora);
  const vista = (lista, prog, tipo) => lista.map((m) => {
    const p = prog[m.id] || {};
    return { id: m.id, tipo, texto: m.texto, meta: m.meta, premio: m.premio, stat: m.stat,
      progreso: Math.min(m.meta, p.v || 0), hecha: !!p.hecha, cobrada: !!p.cobrada };
  });
  return {
    diarias: vista(elegirMisiones(MISIONES_DIARIAS, DIARIAS_POR_DIA, st.dia), st.d, 'diaria'),
    semanales: vista(elegirMisiones(MISIONES_SEMANALES, SEMANALES_POR_SEMANA, st.sem), st.s, 'semanal'),
    segundos_dia: segundosHasta(ahora, false), segundos_semana: segundosHasta(ahora, true),
  };
}
/** Suma una partida a las misiones de la cuenta (la MODIFICA) y devuelve las que se acaban de completar. */
function avanzarMisiones(cu, modo, gano, r, ahora) {
  const st = estadoMisiones(cu, ahora);
  const valores = { partidas: 1, ganadas: gano ? 1 : 0, bajas: r.bajas, dano: r.dano, objetivos: r.objetivos,
    mvp: r.mvp ? 1 : 0, oleada: r.oleada };
  const hechas = [];
  const pasar = (lista, prog) => {
    for (const m of lista) {
      if (m.modo && m.modo !== modo) continue;
      const p = prog[m.id] || { v: 0, hecha: false };
      if (p.hecha) continue;
      const v = valores[m.stat] || 0;
      p.v = m.max ? Math.max(p.v, v) : p.v + v;
      if (p.v >= m.meta) {
        p.hecha = true;              // (se cobra al reclamarla: /mision/reclamar)
        hechas.push({ id: m.id, texto: m.texto, premio: m.premio });
      }
      prog[m.id] = p;
    }
  };
  pasar(elegirMisiones(MISIONES_DIARIAS, DIARIAS_POR_DIA, st.dia), st.d);
  pasar(elegirMisiones(MISIONES_SEMANALES, SEMANALES_POR_SEMANA, st.sem), st.s);
  cu.misiones = { dia: st.dia, d: st.d, sem: st.sem, s: st.s };
  return hechas;
}

// ---------------------------------------------------------------------------
// LO EQUIPADO, EN LA CUENTA. Armas por ranura, skin del mazo, modelo, color y accesorios: al entrar desde
// otro aparato te encuentras equipado igual. Se guarda tal cual lo manda el juego, pero SOLO estos campos
// y con tamaños acotados (no es un almacen libre de datos).
// ---------------------------------------------------------------------------
function limpiarEquipo(e) {
  if (!e || typeof e !== 'object') return null;
  const txt = (v, n) => String(v == null ? '' : v).slice(0, n);
  const out = {};
  if (e.loadout && typeof e.loadout === 'object') {
    out.loadout = {};
    for (const [k, v] of Object.entries(e.loadout).slice(0, 8)) out.loadout[txt(k, 16)] = txt(v, 48);
  }
  if ('skin_mazo' in e) out.skin_mazo = txt(e.skin_mazo, 48);
  if ('avatar_skin' in e) out.avatar_skin = Math.max(0, Math.min(64, parseInt(e.avatar_skin, 10) || 0));
  if ('avatar_tint' in e) out.avatar_tint = txt(e.avatar_tint, 12);
  if (Array.isArray(e.accesorios)) out.accesorios = e.accesorios.slice(0, 12).map((a) => txt(a, 32));
  return out;
}

/** La misma curva que `Settings.nivel()` en el juego: n(n-1)/2 * 1000 acumulado. */
// LA EXP DEL PASE (2026-10-12): aparte de la del jugador, por temporada (cu.pase_exp.t<n>), solo de las tareas.
// Curva plana: PASE_EXP_NIVEL por nivel (= PaseBatalla.EXP_NIVEL en el juego).
const PASE_EXP_NIVEL = 4000;
function expPase(c) { return (c.pase_exp && c.pase_exp['t' + temporadaPase()]) || 0; }
function nivelPase(c) { return Math.floor(expPase(c) / PASE_EXP_NIVEL) + 1; }
function nivelDe(exp) { return Math.floor((1 + Math.sqrt(1 + 8 * (exp || 0) / 1000)) / 2); }

// ---------------------------------------------------------------------------
// Freno de peticiones. En memoria y por instancia: no es una defensa perfecta, pero corta el bucle
// accidental del cliente, que es de lo que de verdad hay que protegerse para no gastar la cuota.
// ---------------------------------------------------------------------------
const golpes = new Map();
function demasiado(ip, limite, ventanaMs) {
  const ahora = Date.now();
  const k = ip;
  const e = golpes.get(k);
  if (!e || ahora > e.hasta) { golpes.set(k, { n: 1, hasta: ahora + ventanaMs }); return false; }
  e.n++;
  if (golpes.size > 10000) golpes.clear();
  return e.n > limite;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
function responder(res, codigo, obj) {
  const cuerpo = JSON.stringify(obj);
  res.writeHead(codigo, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(cuerpo),
    'Cache-Control': 'no-store',
  });
  res.end(cuerpo);
}

function leerCuerpo(req, tope = 4096) {
  return new Promise((ok, mal) => {
    let n = 0; const trozos = [];
    req.on('data', (d) => {
      n += d.length;
      if (n > tope) { mal(new Error('cuerpo demasiado grande')); req.destroy(); return; }
      trozos.push(d);
    });
    req.on('end', () => { try { ok(JSON.parse(Buffer.concat(trozos).toString('utf8') || '{}')); } catch { mal(new Error('json invalido')); } });
    req.on('error', mal);
  });
}

// CUENTAS BLOQUEADAS DESDE EL PANEL (2026-10-05, pedido: "bloquee mi cuenta y en el lobby nunca salio el cartel"): en
// memoria, usuario -> motivo. Lo apunta el panel al bloquear (avisarBloqueo) y cuentaDeToken si lee una bloqueada (tras
// reiniciar el servidor). Con una sesion de una cuenta de aqui, el latido y cualquier peticion responden 403
// {bloqueada: true, motivo}: el juego enseña CUENTA BLOQUEADA y cierra la sesion. Antes era un 401 "sesion no valida" mudo.
const bloqueos = new Map();
function errorBloqueada(motivo) {
  const e = new Error('cuenta bloqueada');
  e.bloqueada = true;
  e.motivo = motivo || '';
  return e;
}
function responderBloqueada(res, motivo) {
  return responder(res, 403, { error: 'cuenta bloqueada' + (motivo ? ': ' + motivo : ''), bloqueada: true, motivo: motivo || '' });
}

async function cuentaDeToken(req) {
  const cab = req.headers['authorization'] || '';
  const usuario = leerToken(cab.startsWith('Bearer ') ? cab.slice(7) : '');
  if (!usuario) return null;
  const c = deCache(usuario) || await leer(objetoDe(usuario));
  if (!c) return null;
  if (c.datos.bloqueada) {                      // BLOQUEADA desde el panel: fuera, y que el juego sepa por que
    if (bloqueos.size > 20000) bloqueos.clear();
    bloqueos.set(usuario, c.datos.motivo_bloqueo || '');
    throw errorBloqueada(c.datos.motivo_bloqueo);
  }
  bloqueos.delete(usuario);
  aCache(usuario, c.datos, c.generacion);
  if (admin) await admin.cargarTodos(false);
  return { usuario, ...c };
}

/**
 * Lee-modifica-escribe con reintento. Es el corazon de que no se pierda un premio: si entre la
 * lectura y la escritura alguien mas toco la cuenta, la precondicion falla y se vuelve a empezar
 * SOBRE EL DATO NUEVO, en vez de machacarlo.
 */
async function actualizar(usuario, cambiar, intentos = 4) {
  for (let i = 0; i < intentos; i++) {
    const act = await leer(objetoDe(usuario));
    if (!act) return { error: 'no existe' };
    const copia = JSON.parse(JSON.stringify(act.datos));
    const r = cambiar(copia);
    if (r && r.error) return r;
    const gen = await escribir(objetoDe(usuario), copia, act.generacion);
    if (gen !== null) { aCache(usuario, copia, gen); return { cuenta: copia, extra: r }; }
    await new Promise((s) => setTimeout(s, 20 * (i + 1)));   // alguien se adelanto: reintentar
  }
  return { error: 'ocupado' };
}

/**
 * La pagina que ve el jugador al terminar con Google, y que devuelve el token AL JUEGO.
 *
 * El juego tiene abierto un puerto en 127.0.0.1 esperando; esta pagina redirige el navegador ahi con
 * el token. Es la forma estandar para aplicaciones de escritorio ("loopback"): no hace falta que el
 * juego incruste un navegador ni que el usuario copie y pegue nada.
 */
function paginaFin(res, datos, error) {
  // Con `codigo` (movil) NO se redirige a ninguna parte: el juego recogera el token el solo. Con
  // puerto (PC) se devuelve el navegador al juego, que sigue escuchando.
  const destino = (datos && datos.puerto && !datos.codigo)
    ? `http://127.0.0.1:${datos.puerto}/?token=${encodeURIComponent(datos.token)}` : '';
  const html = `<!doctype html><meta charset="utf-8">
<title>Breach</title>
<style>body{background:#0d0f13;color:#e8eaf0;font:16px system-ui;display:grid;place-items:center;height:100vh;margin:0;text-align:center}
b{color:#ffd400;font-size:28px;display:block;margin-bottom:12px}</style>
<b>BREACH</b>
${error ? `<p>${error}</p>` : '<p><b style="font-size:20px">Listo.</b><br>Ya puedes <b>volver al juego</b>.<br><span style="opacity:.6;font-size:14px">Cierra esta pestaña o pulsa atrás.</span></p>'}
${destino ? `<script>location.replace(${JSON.stringify(destino)})</script>` : ''}`;
  res.writeHead(error ? 400 : 200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(html);
}

// ---------------------------------------------------------------------------
// LISTA DE SALAS (partidas entre casas distintas)
//
// El juego encontraba salas gritando por UDP a su propia red. Ese grito no sale del router, asi que
// dos personas en dos casas no se veian nunca por muy "online" que fuera la cuenta. Aqui se apunta
// quien tiene una sala abierta y con que direccion publica, y el que busca la lee desde donde sea.
//
// TODO ESTO VIVE EN MEMORIA, a proposito:
//  - una sala dura minutos y cambia cada pocos segundos; escribirla en el almacen se comeria la
//    cuota de escrituras, que es el recurso escaso de este proyecto (5.000 al mes);
//  - si la instancia se duerme y se pierde la lista, no pasa nada: cada anfitrion vuelve a anunciarse
//    al siguiente latido y en 10 segundos la lista esta rehecha.
//
// La direccion IP NO la manda el cliente: la lee el servidor de la conexion. Un cliente puede mentir
// sobre su nombre, pero no sobre desde donde se conecta.
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// TOKENS DE GOOGLE A LA ESPERA DE QUE EL JUEGO LOS RECOJA
//
// Antes el navegador devolvia el token a un puerto que el juego abria en 127.0.0.1. En un PC funciona;
// EN ANDROID NO: al abrir el navegador, el juego pasa a segundo plano y el sistema lo congela, asi que
// cuando el navegador llama a ese puerto no hay nadie escuchando. El jugador entraba en Google, volvia
// al juego y seguia sin sesion.
//
// Ahora el token se guarda aqui un minuto bajo un codigo que el juego eligio ANTES de abrir el
// navegador, y el juego lo recoge cuando vuelve a estar en primer plano. El codigo es de un solo uso.
const RECOGER_MS = 120000;
const recoger = new Map();     // codigo -> { token, hasta }

function limpiarRecoger() {
  const ahora = Date.now();
  for (const [k, v] of recoger) if (ahora > v.hasta) recoger.delete(k);
}

const SALA_VIVA_MS = 25000;        // sin latido en 25 s, la sala se da por muerta
const TOPE_SALAS = 500;
const salas = new Map();           // id -> sala

function limpiarSalas() {
  const ahora = Date.now();
  for (const [id, s] of salas) if (ahora - s.visto > SALA_VIVA_MS) salas.delete(id);
}

// ¿SE PUEDE ENTRAR A ESTA SALA DESDE FUERA?
//
// Dos caminos, y basta con uno: que el router del anfitrion tenga el puerto abierto (UPnP), o que
// sepamos su direccion publica de UDP (STUN) para hacer el agujero.
//
// Sin ninguno de los dos NO se ofrece la sala. La `ip` que ve este servidor no vale como respaldo:
// aqui se llega por HTTP -y muchas veces por IPv6, medido en produccion-, y la partida va por UDP
// sobre IPv4. Ofrecerla dejaria al que entra mirando un "conectando..." que no termina nunca.
function alcanzable(s) {
  return directa(s) || s.puente === true;
}
// ...por el camino directo (UDP). Si no, todavia se entra por el PUENTE (puente.js) si el anfitrion lo admite
function directa(s) {
  return s.abierta === true || !!(s.pubIp && s.pubPuerto);
}

function salaPublica(s) {
  return {
    id: s.id, nombre: s.nombre, mapa: s.mapa, modo: s.modo, sub: s.sub || '', pers: s.pers === true,
    jugadores: s.jugadores, max: s.max, jugando: s.jugando,
    ip: s.pubIp || s.ip, puerto: s.pubPuerto || s.puerto,
    abierta: alcanzable(s), anfitrion: s.anfitrion,
  };
}

function limpiarTexto(t, tope) {
  return String(t == null ? '' : t).replace(/[ -]/g, '').trim().slice(0, tope);
}


// ---------------------------------------------------------------------------
// AMIGOS (2026-09-28). Cada cuenta lleva:
//   id_pub   su ID de 6 cifras, el que se comparte; con su indice `ids/<id>.json` -> usuario (se da la primera
//            vez que abre los amigos: una escritura por cuenta y para siempre)
//   amigos   [usuario, ...]           tope AMIGOS_MAX
//   sol_rec  [{de: usuario, t}]       invitaciones recibidas, tope SOLICITUDES_MAX
//   sol_env  [{a: usuario, t}]        enviadas, tope SOLICITUDES_MAX
// Hacia fuera NUNCA sale el `usuario` (es con lo que se entra): solo el ID, el nombre, el nivel y el aspecto.
//
// LA PRESENCIA (en el lobby, jugando, desconectado hace...) vive EN MEMORIA, como las salas: cada peticion con
// sesion la apunta y `/latido` la refresca, sin escribir nada. Si la instancia se duerme se pierde, y se usa
// la ultima partida de la cuenta (`ultima`) para el "desconectado hace".
// ---------------------------------------------------------------------------
const AMIGOS_MAX = 50;
const SOLICITUDES_MAX = 25;
const PRESENCIA_VIVA_MS = 150000;
const presencia = new Map();          // usuario -> { t, donde }
// LOS AVISOS: la invitacion recien mandada, para que le salga al otro en el lobby (el latido se la lleva). En
// memoria, como la presencia; la invitacion de verdad esta en su cuenta y la vera en AMIGOS pase lo que pase.
const avisos = new Map();             // usuario -> [{ t, ficha }]
function avisar(usuario, ficha) {
  if (avisos.size > 20000) avisos.clear();
  const l = (avisos.get(usuario) || []).filter((a) => a.ficha.id !== ficha.id).slice(-4);
  l.push({ t: Date.now(), ficha });
  avisos.set(usuario, l);
}
function apuntarPresencia(usuario, donde) {
  if (presencia.size > 20000) presencia.clear();
  presencia.set(usuario, { t: Date.now(), donde: donde === 'partida' ? 'partida' : 'lobby' });
}
function claveId(id) { return `ids/${id}.json`; }
function idCandidato(usuario, intento) {
  const h = crypto.createHash('sha256').update(SECRETO + ':' + usuario + ':' + intento).digest();
  return 100000 + (h.readUInt32BE(0) % 900000);
}
/** El ID de 6 cifras de la cuenta; si aun no tiene, se le da uno libre (indice atomico: ifGenerationMatch=0). */
async function asegurarId(c) {
  if (c.datos.id_pub) return c.datos.id_pub;
  for (let i = 0; i < 10; i++) {
    const id = idCandidato(c.usuario, i);
    let mio = (await escribir(claveId(id), { usuario: c.usuario }, '0')) !== null;
    if (!mio) { const act = await leer(claveId(id)); mio = !!(act && act.datos && act.datos.usuario === c.usuario); }
    if (!mio) continue;
    const r = await actualizar(c.usuario, (cu) => { cu.id_pub = id; return {}; });
    if (r.cuenta) c.datos = r.cuenta;
    return id;
  }
  return null;
}
/** Otra cuenta, para enseñarla (con la cache: abrir los amigos dos veces no baja las cuentas dos veces). */
async function cuentaAjena(usuario) {
  const e = deCache(usuario) || await leer(objetoDe(usuario));
  if (!e) return null;
  aCache(usuario, e.datos, e.generacion);
  return e.datos;
}
/** Lo que se enseña de un jugador: nada con lo que se pueda entrar en su cuenta. */
function fichaAmigo(d, usuario) {
  const ahora = Date.now();
  const p = presencia.get(usuario);
  let estado = 'desconectado';
  let hace = null;
  if (p && ahora - p.t < PRESENCIA_VIVA_MS) estado = p.donde;
  else {
    const ult = Math.max(p ? p.t : 0, Date.parse(d.ultima || '') || 0);
    if (ult > 0) hace = Math.max(0, Math.floor((ahora - ult) / 1000));
  }
  const eq = d.equipo || {};
  return { id: d.id_pub || null, nombre: d.nombre || '', nivel: nivelDe(d.exp), estado, hace,
    skin: eq.avatar_skin || 0 };
}
/** De lo que escribe el jugador al usuario: el ID de 6 cifras o el apodo exacto. */
async function usuarioDeBusqueda(q) {
  // (2026-10-15, bug: "busco a mi amigo, lo encuentro y al invitarlo dice que no existe"): el juego lee el ID como
  // numero y lo devuelve como "888264.0"; se le quita el ".0"
  const t = String(q == null ? '' : q).trim().replace(/^(\d{6})\.0+$/, '$1');
  if (/^\d{6}$/.test(t)) {
    const e = await leer(claveId(t));
    return e && e.datos ? e.datos.usuario : null;
  }
  const n = normalizarNombre(t);
  if (!n) return null;
  const e = await leer(claveNombre(n));
  return e && e.datos ? e.datos.usuario : null;
}
async function listaAmigos(c) {
  const d = c.datos;
  const fichas = async (usuarios) => {
    const out = [];
    for (const u of usuarios) {
      const a = await cuentaAjena(u);
      if (a) out.push(fichaAmigo(a, u));
    }
    return out;
  };
  const amigos = await fichas(d.amigos || []);
  const recibidas = await fichas((d.sol_rec || []).map((x) => x.de));
  const enviadas = await fichas((d.sol_env || []).map((x) => x.a));
  // SUGERIDOS: los que han estado conectados hace poco (y no son ya amigos ni estan invitados), de la cache:
  // no se baja ninguna cuenta para esto
  const fuera = new Set([c.usuario, ...(d.amigos || []), ...(d.sol_rec || []).map((x) => x.de), ...(d.sol_env || []).map((x) => x.a)]);
  const sugeridos = [];
  const recientes = [...presencia.entries()].sort((a, b) => b[1].t - a[1].t);
  for (const [u, pr] of recientes) {
    if (sugeridos.length >= 10 || Date.now() - pr.t > 3600000) break;
    if (fuera.has(u)) continue;
    const e = deCache(u);
    if (e && e.datos && e.datos.id_pub) sugeridos.push(fichaAmigo(e.datos, u));
  }
  return { mi_id: d.id_pub || null, amigos, recibidas, enviadas, sugeridos,
    max_amigos: AMIGOS_MAX, max_solicitudes: SOLICITUDES_MAX };
}

// ---------------------------------------------------------------------------
// EL PANEL DE ADMINISTRACION (admin.js) y el aviso al juego: la cuenta que toca el panel se apunta aqui y el
// siguiente latido de ese jugador le dice que vuelva a pedir su perfil (asi ve el oro nuevo o el regalo sin salir).
// ---------------------------------------------------------------------------
const cambiadas = new Set();

// ---------------------------------------------------------------------------
// ESPECTAR (2026-09-29, pedido: "en el panel, cuando hay una partida en curso, un boton para espectar que me abra el
// juego y entre solo en la partida en modo espectador"). El panel no puede dibujar una partida: la mira el JUEGO,
// con la cuenta del juego del administrador (`admin/config.json` -> espectador). El recorrido:
//   1. el panel pide /admin/espectar {sala}: aqui se apunta una ORDEN para esa cuenta (en memoria, 2 minutos) con un
//      TICKET firmado (cuenta + sala + caducidad, 10 minutos), y el panel abre el juego;
//   2. el juego la recoge en el latido (`espectar`) o al volver al primer plano (/espectar/pendiente);
//   3. entra en la sala por el mismo camino que un jugador (lista de salas + llamada + UDP directo) y se presenta
//      con el ticket; el ANFITRION lo comprueba aqui (/espectar/verificar) antes de tratarlo como espectador.
// El servidor no lleva la partida: solo firma quien puede mirarla.
// ---------------------------------------------------------------------------
const ORDEN_ESPECTAR_MS = 120000;
const TICKET_ESPECTAR_MS = 600000;
const ordenesEspectar = new Map();    // usuario -> { sala, mapa, ticket, hasta }  (la cuenta configurada: el panel en el PC)
// POR APARATO (2026-10-02, pedido: "que mire que cuenta estoy usando"; y el fallo: con un amigo en la misma wifi la orden
// fue a SU cuenta -la configurada- y su juego salio de la partida para ir a mirar). El panel manda la huella de SU
// telefono (el ANDROID_ID es el mismo para las dos apps porque se firman con la misma llave) y la orden se la lleva el
// Breach de ese mismo telefono, con la cuenta que tenga abierta. Nunca un juego en partida ni el anfitrion de esa sala.
const ordenesAparato = new Map();     // huella del aparato -> { sala, mapa, hasta }
let configAdmin = null;               // { espectador } (admin/config.json), se lee una vez
async function leerConfigAdmin() {
  if (configAdmin) return configAdmin;
  try {
    const e = await leer('admin/config.json');
    configAdmin = (e && e.datos) || {};
  } catch (err) { console.error('[admin] no se pudo leer la config', err.message); configAdmin = {}; }
  return configAdmin;
}
async function guardarConfigAdmin(nueva) {
  await escribir('admin/config.json', nueva, null);
  configAdmin = nueva;
}
function ticketEspectar(usuario, sala) {
  const cuerpo = Buffer.from(JSON.stringify({ u: usuario, s: sala, c: Date.now() + TICKET_ESPECTAR_MS })).toString('base64url');
  return cuerpo + '.' + crypto.createHmac('sha256', SECRETO).update('esp:' + cuerpo).digest('base64url');
}
function leerTicketEspectar(t) {
  const [cuerpo, firma] = String(t || '').split('.');
  if (!cuerpo || !firma) return null;
  const buena = crypto.createHmac('sha256', SECRETO).update('esp:' + cuerpo).digest('base64url');
  if (!igualesEnTiempoFijo(firma, buena)) return null;
  try {
    const d = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
    return Date.now() < d.c ? d : null;
  } catch { return null; }
}
function huellaValida(h) { return typeof h === 'string' && /^[a-f0-9]{16,64}$/.test(h); }
/** La orden pendiente para este juego (se entrega UNA vez): la de SU aparato, y si no, la de su cuenta (la configurada).
 *  `enPartida`: un juego que esta jugando no la recoge (no se le saca de su partida). */
function tomarOrdenEspectar(usuario, aparato, enPartida) {
  if (enPartida) return null;
  if (huellaValida(aparato) && ordenesAparato.has(aparato)) {
    const oa = ordenesAparato.get(aparato);
    const s = salas.get(oa.sala);
    if (s && s.cuenta && s.cuenta === usuario) return null;     // el anfitrion no se mira a si mismo
    ordenesAparato.delete(aparato);
    if (Date.now() < oa.hasta) return { sala: oa.sala, mapa: oa.mapa, ticket: ticketEspectar(usuario, oa.sala) };
  }
  const o = ordenesEspectar.get(usuario);
  if (!o) return null;
  const s2 = salas.get(o.sala);
  if (s2 && s2.cuenta && s2.cuenta === usuario) return null;
  ordenesEspectar.delete(usuario);
  return Date.now() < o.hasta ? { sala: o.sala, mapa: o.mapa, ticket: o.ticket } : null;
}
/** `aparato`: la huella del telefono del panel (si la hay, manda ella); si no, la cuenta configurada `usuario`. */
function ordenarEspectar(usuario, sala, aparato) {
  if (huellaValida(aparato)) {
    if (ordenesAparato.size > 1000) ordenesAparato.clear();
    const oa = { sala: sala.id, mapa: sala.mapa || '', hasta: Date.now() + ORDEN_ESPECTAR_MS };
    ordenesAparato.set(aparato, oa);
    return oa;
  }
  if (!usuario) return null;
  if (ordenesEspectar.size > 1000) ordenesEspectar.clear();
  const o = { sala: sala.id, mapa: sala.mapa || '', ticket: ticketEspectar(usuario, sala.id), hasta: Date.now() + ORDEN_ESPECTAR_MS };
  ordenesEspectar.set(usuario, o);
  cambiadas.add(usuario);        // el siguiente latido le dice que mire (y /espectar/pendiente, al volver al juego)
  return o;
}

// LOS REPORTES DE JUGADORES y los ME GUSTA del final (reportes.js): /reporte y /likes aqui, y el panel en admin.js
const reportes = require('./reportes.js')({ SECRETO, leer, escribir, listar, cuentaAjena, cuentaDeToken, usuarioDeBusqueda,
  actualizar, nivelDe, responder, leerCuerpo, demasiado });
// HABLAR CON NOSOTROS (contacto.js): /contacto aqui (con o sin sesion) y el panel en admin.js (/admin/mensajes)
const contacto = require('./contacto.js')({ leer, escribir, listar, cuentaAjena, cuentaDeToken, nivelDe, responder,
  leerCuerpo, demasiado });

const admin = require('./admin.js')({
  SECRETO, leer, escribir, borrarObjeto, listar, aCache, borrarCache, cuentaAjena, actualizar, reportes, contacto,
  hashClave, igualesEnTiempoFijo, normalizarUsuario, normalizarNombre, claveNombre, claveValida, objetoDe,
  reservarNombre, soltarNombre, nivelDe, perfilPublico, PRECIOS, CATALOGO, presencia, PRESENCIA_VIVA_MS,
  salas, responder, leerCuerpo, demasiado, claveId, PROGRESO, darCarta,
  tienda: { ajustes: () => TIENDA, guardar: guardarTienda, PACKS, preciosPacks, moneda: () => MP_MONEDA, precioDe, nombreDe, juegoFabrica, validarJuego, validarDestacados },
  espectar: { leerConfig: leerConfigAdmin, guardarConfig: guardarConfigAdmin, ordenar: ordenarEspectar, limpiarSalas, alcanzable },
  avisarCambio: (u) => { if (cambiadas.size > 20000) cambiadas.clear(); cambiadas.add(u); },
  avisarBloqueo: (u, bloqueada, motivo) => { if (bloqueada) bloqueos.set(u, motivo || ''); else bloqueos.delete(u); },
});

// EL EQUIPO (equipos.js): FORMAR EQUIPO con amigos conectados, invitaciones con cuenta atras y la sala del lider
// EL PUENTE (puente.js): la partida por WebSocket cuando el camino directo (UDP) no se abre. Entra por 'upgrade', abajo
const puente = require('./puente.js')({ leer, escribir, leerToken, salas });

const equipos = require('./equipos.js')({
  leerToken, cuentaDeToken, cuentaAjena, usuarioDeBusqueda, nivelDe, presencia, PRESENCIA_VIVA_MS,
  apuntarPresencia, responder, leerCuerpo, demasiado,
});

// LOS TORNEOS SEMANALES y el aviso de "hay gente jugando" (torneos.js): /torneo y /admin/torneo*
const torneos = require('./torneos.js')({ leer, escribir, leerToken, actualizar, nivelDe, responder, leerCuerpo, salas,
  regaloDe: (b) => admin.regaloDe(b), avisarCambio: (u) => { if (cambiadas.size > 20000) cambiadas.clear(); cambiadas.add(u); } });

const servidor = http.createServer(async (req, res) => {
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
  const url = new URL(req.url, 'http://x');
  const ruta = url.pathname;
  try {
    if (ruta === '/salud') return responder(res, 200, { ok: true, version: 1, puente: puente.estado() });

    if (req.method !== 'POST' && !ruta.startsWith('/admin/') && !['/torneo', '/perfil', '/config', '/google/inicio', '/google/callback', '/salas', '/pago/packs', '/pago/aviso', '/pago/vuelta', '/amigos', '/tienda', '/apk/info', '/apk/Breach.apk', '/parche/info', '/parche/Breach.pck', '/parche/Breach_pc.pck', '/parche/motor_android', '/parche/motor_windows', '/parche/admin/info', '/parche/admin/Admin.pck'].includes(ruta))
      return responder(res, 404, { error: 'no existe' });
    if (demasiado(ip, 120, 60000)) return responder(res, 429, { error: 'demasiadas peticiones' });

    // ---------------------------------------------------------------- los torneos (torneos.js)
    if (ruta === '/torneo') return await torneos.rutas(req, res, ruta, url);
    if (ruta.startsWith('/admin/torneo')) {
      if (!admin.tokenAdminValido(req)) return responder(res, 401, { error: 'sesion del panel caducada' });
      return await torneos.rutas(req, res, ruta, url);
    }
    // ---------------------------------------------------------------- panel de administracion
    if (ruta.startsWith('/admin/')) return await admin.rutas(req, res, ruta, url, ip);
    // ---------------------------------------------------------------- el equipo (equipos.js)
    if (ruta.startsWith('/grupo/') && req.method === 'POST') return await equipos.rutas(req, res, ruta, ip);
    // ---------------------------------------------------------------- reportes y me gusta (reportes.js)
    if (ruta === '/reporte' || ruta === '/likes' || ruta === '/trampa') return await reportes.rutas(req, res, ruta);
    if (ruta === '/contacto') return await contacto.rutas(req, res, ip);

    // LOS AJUSTES DE LA TIENDA que puso el panel (precios y nombres). Sin sesion: es un catalogo.
    if (ruta === '/tienda' && req.method === 'GET') {
      return responder(res, 200, { v: TIENDA.v, precios: TIENDA.precios, nombres: TIENDA.nombres,
        destacados: TIENDA.destacados || [], juego: TIENDA.juego || {} });
    }

    // ---------------------------------------------------------------- reclamar los regalos del panel
    // CANJEAR UN CODIGO (admin.js, "los codigos"): sus articulos entran como regalos de la cuenta
    if (ruta === '/codigo/canjear' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('codigo:' + c.usuario, 8, 60000) || demasiado('codigo-ip:' + ip, 20, 60000)) return responder(res, 429, { error: 'demasiados intentos: espera un minuto' });
      const b = await leerCuerpo(req);
      const r = await admin.canjear(c.usuario, b.codigo);
      if (r.error) return responder(res, 400, { error: r.error });
      const e = await leer(objetoDe(c.usuario));
      return responder(res, 200, { regalos: r.regalos, perfil: e && e.datos ? perfilPublico(e.datos) : null });
    }
    // ---------------------------------------------------------------- LA APK, DESDE ESTE SERVIDOR (2026-10-16, pedido: "me
    // canse de pasar APK por APK: que el servidor de la PC actualice la APK vieja"). tools/publicar_apk.py deja en
    // servidor/apk/ el ultimo Breach.apk y version.json ({code, nombre, mb, fecha}). El juego pregunta /apk/info al abrir
    // el lobby y, si su version es menor, el aviso lo manda a /apk/Breach.apk (el navegador lo baja y Android pide
    // "Instalar": una app no puede instalarse sola). Sin sesion: lo pide tambien quien aun no ha entrado.
    if (ruta === '/apk/info' && req.method === 'GET') {
      try {
        const v = JSON.parse(fs.readFileSync(path.join(__dirname, 'apk', 'version.json'), 'utf8'));
        return responder(res, 200, v);
      } catch (e) {
        return responder(res, 404, { error: 'no hay apk publicada' });
      }
    }
    // LOS PARCHES (2026-10-16, godot/scripts/parche.gd): solo los archivos que cambiaron, para UNA version de APK.
    // tools/publicar_parche.py deja servidor/apk/parche.pck y parche.json ({apk, n, mb, sha256, fecha}).
    if (ruta === '/parche/info' && req.method === 'GET') {
      try {
        // el PC tiene su propio parche (tools/publicar_parche.py lo deja en parche_pc.json / parche_pc.pck)
        const pc = url.searchParams.get('plat') === 'pc';
        return responder(res, 200, JSON.parse(fs.readFileSync(path.join(__dirname, 'apk', pc ? 'parche_pc.json' : 'parche.json'), 'utf8')));
      } catch (e) {
        return responder(res, 404, { error: 'no hay parche' });
      }
    }
    // LOS PARCHES DEL PANEL (2026-10-28, admin/scripts/parche_admin.gd; los deja tools/publicar_parche_admin.py)
    if (ruta === '/parche/admin/info' && req.method === 'GET') {
      try { return responder(res, 200, JSON.parse(fs.readFileSync(path.join(__dirname, 'apk', 'admin_parche.json'), 'utf8'))); }
      catch (e) { return responder(res, 404, { error: 'no hay parche' }); }
    }
    const RUTAS_DESCARGA = { '/parche/admin/Admin.pck': 'admin_parche.pck', '/apk/Breach.apk': 'Breach.apk', '/parche/Breach.pck': 'parche.pck', '/parche/Breach_pc.pck': 'parche_pc.pck',
      '/parche/motor_android': 'motor_android', '/parche/motor_windows': 'motor_windows' };   // el motor C++ del parche
    // LA APK DESDE OTRO SITIO (2026-10-16, pedido: "que le de el link de Mediafire"): si version.json trae `url`, el
    // boton ACTUALIZAR de cualquier version (las viejas abren siempre /apk/Breach.apk) va ahi
    if (ruta === '/apk/Breach.apk') {
      try {
        const v = JSON.parse(fs.readFileSync(path.join(__dirname, 'apk', 'version.json'), 'utf8'));
        if (v.url) { res.writeHead(302, { Location: v.url, 'Cache-Control': 'no-cache' }); return res.end(); }
      } catch (e) {}
    }
    if (RUTAS_DESCARGA[ruta] && (req.method === 'GET' || req.method === 'HEAD')) {
      const f = path.join(__dirname, 'apk', RUTAS_DESCARGA[ruta]);
      let st;
      try { st = fs.statSync(f); } catch (e) { return responder(res, 404, { error: 'no hay apk publicada' }); }
      // con "Range" (el navegador reanuda una descarga cortada)
      const rango = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range || ''));
      let ini = 0, fin = st.size - 1, codigo = 200;
      if (rango && (rango[1] || rango[2])) {
        ini = rango[1] ? parseInt(rango[1], 10) : Math.max(0, st.size - parseInt(rango[2], 10));
        fin = rango[1] && rango[2] ? Math.min(parseInt(rango[2], 10), st.size - 1) : st.size - 1;
        if (!(ini >= 0 && ini <= fin)) { res.writeHead(416, { 'Content-Range': 'bytes */' + st.size }); return res.end(); }
        codigo = 206;
      }
      const esApk = ruta === '/apk/Breach.apk';
      const cab = { 'Content-Type': esApk ? 'application/vnd.android.package-archive' : 'application/octet-stream', 'Content-Length': fin - ini + 1,
        'Content-Disposition': 'attachment; filename="' + (esApk ? 'Breach.apk' : 'Breach.pck') + '"', 'Accept-Ranges': 'bytes', 'Cache-Control': 'no-cache' };
      if (codigo === 206) cab['Content-Range'] = 'bytes ' + ini + '-' + fin + '/' + st.size;
      res.writeHead(codigo, cab);
      if (req.method === 'HEAD') return res.end();
      console.log(esApk ? '[apk] descarga' : '[parche] descarga', ip, codigo === 206 ? ('desde ' + ini) : 'entera');
      // si el movil corta la descarga, el archivo se CIERRA (2026-11-01: con .pipe() a secas se quedaba abierto y
      // Windows no dejaba reemplazar parche.pck al publicar el siguiente: "Acceso denegado")
      const flujo = fs.createReadStream(f, { start: ini, end: fin });
      res.on('close', () => flujo.destroy());
      flujo.on('error', () => { try { res.destroy(); } catch (e) {} });
      return flujo.pipe(res);
    }

    if (ruta === '/regalo/reclamar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const ids = Array.isArray(b.ids) ? b.ids.map((x) => String(x).slice(0, 24)).slice(0, 50) : [];
      const r = await admin.reclamar(c.usuario, ids);
      if (r.error) return responder(res, 503, { error: r.error });
      console.log('[regalo] reclamados', c.usuario, (r.extra.reclamados || []).length);
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), reclamados: r.extra.reclamados || [] });
    }

    // ---------------------------------------------------------------- salas
    // ANUNCIAR / LATIDO. La misma ruta hace las dos cosas: si mandas el id que te dieron, refrescas
    // la sala; si no, se crea una nueva. Asi el cliente no tiene que llevar dos caminos.
    // RECOGER EL TOKEN. El juego pregunta "¿ya esta lo mio?" con el codigo que eligio antes de abrir
    // el navegador. Es de UN SOLO USO: en cuanto se entrega, se borra.
    if (ruta === '/google/recoger' && req.method === 'POST') {
      limpiarRecoger();
      const b = await leerCuerpo(req);
      const cod = String(b.codigo || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 32);
      if (!cod) return responder(res, 400, { error: 'falta el codigo' });
      const e = recoger.get(cod);
      if (!e) return responder(res, 202, { esperando: true });
      recoger.delete(cod);
      return responder(res, 200, { token: e.token });
    }

    if (ruta === '/salas/anunciar' && req.method === 'POST') {
      const b = await leerCuerpo(req);
      limpiarSalas();
      const puerto = parseInt(b.puerto, 10);
      if (!(puerto > 0 && puerto < 65536)) return responder(res, 400, { error: 'puerto no valido' });
      let s = (b.id && salas.get(String(b.id))) || null;
      if (s && s.llave !== String(b.llave || '')) return responder(res, 403, { error: 'esa sala no es tuya' });
      if (!s) {
        if (salas.size >= TOPE_SALAS) return responder(res, 503, { error: 'lista llena, prueba en un momento' });
        s = { id: crypto.randomBytes(8).toString('hex'), llave: crypto.randomBytes(16).toString('hex'), creada: Date.now() };
        salas.set(s.id, s);
      }
      s.nombre = limpiarTexto(b.nombre, 32) || 'Sala';
      s.anfitrion = limpiarTexto(b.anfitrion, 24);
      // la CUENTA del anfitrion, si viene con sesion: una orden de espectar esta sala nunca es para el (ver ESPECTAR)
      {
        const cabA = req.headers['authorization'] || '';
        const uA = cabA.startsWith('Bearer ') ? leerToken(cabA.slice(7)) : null;
        if (uA) s.cuenta = uA;
      }
      s.mapa = limpiarTexto(b.mapa, 32);
      s.modo = limpiarTexto(b.modo, 16);
      // EL SUBMODO de la sala (solo/escuadra en battle royale, equipos/todos en duelo): el que busca prefiere el suyo
      s.sub = limpiarTexto(b.sub, 12);
      s.pers = b.pers === true;   // sala personalizada (SALAS): JUGAR no entra en ellas
      s.jugadores = Math.max(0, Math.min(64, parseInt(b.jugadores, 10) || 0));
      s.max = Math.max(2, Math.min(64, parseInt(b.max, 10) || 8));
      s.jugando = b.jugando === true;
      // ABIERTA = el anfitrion consiguio que su router dejara pasar el puerto (UPnP). Si no, la sala
      // se apunta igual pero avisada: hay redes donde solo entra quien este en la misma casa.
      s.abierta = b.abierta === true;
      // PUENTE: el juego del anfitrion admite invitados por el puente (puente.js) aunque su router no deje pasar nada
      s.puente = b.puente === true;
      s.ip = ip;
      s.puerto = puerto;
      // DIRECCION PUBLICA UDP, la que dijo el STUN. No es la misma que `ip:puerto`: por ahi va HTTP
      // sobre TCP, y el router abre un agujero distinto para cada cosa. Para llamar a esta sala hay
      // que usar esta, no aquella.
      if (b.pub_ip && b.pub_puerto) {
        s.pubIp = limpiarTexto(b.pub_ip, 45);
        s.pubPuerto = Math.max(1, Math.min(65535, parseInt(b.pub_puerto, 10) || 0));
      }
      s.visto = Date.now();
      // ...y se le entregan las llamadas de quien quiere entrar, para que el anfitrion les mande su
      // paquete y su router los apunte como invitados. Se entregan UNA VEZ y se vacian.
      const llamadas = s.llamadas || [];
      s.llamadas = [];
      // `puente`: alguien espera en el PUENTE de esta sala (puente.js) y el anfitrion tiene que conectarse a el
      return responder(res, 200, { id: s.id, llave: s.llave, ip: s.ip, llamadas, puente: puente.pide(s.id) });
    }

    if (ruta === '/salas' && req.method === 'GET') {
      limpiarSalas();
      const mapa = limpiarTexto(url.searchParams.get('mapa'), 32);
      let lista = [...salas.values()];
      if (mapa) lista = lista.filter((s) => s.mapa === mapa);
      lista = lista.filter(alcanzable);
      // primero las que tienen gente y hueco: rellenar antes que repartir
      lista.sort((a, b2) => (b2.jugadores - a.jugadores));
      return responder(res, 200, { salas: lista.slice(0, 50).map(salaPublica) });
    }

    // LLAMAR A UNA SALA: "quiero entrar, esta es mi direccion". El servidor se la guarda al anfitrion
    // y le devuelve a este la del anfitrion. Es TODO lo que hace de intermediario: los dos se llaman
    // a la vez, sus routers se apuntan mutuamente como invitados, y a partir de ahi hablan solos.
    if (ruta === '/salas/llamar' && req.method === 'POST') {
      limpiarSalas();
      const b = await leerCuerpo(req);
      const s = salas.get(String(b.id || ''));
      if (!s) return responder(res, 404, { error: 'esa sala ya no existe' });
      const puerto = parseInt(b.puerto, 10);
      if (!(puerto > 0 && puerto < 65536)) return responder(res, 400, { error: 'puerto no valido' });
      // LA IP BUENA ES LA DEL STUN, NO LA QUE VEO YO.
      //
      // Aqui se llega por HTTP, y muchos moviles entran POR IPv6 (medido: las llamadas llegaban como
      // 2803:9800:...). La partida va por UDP sobre IPv4, asi que apuntar la IP de esta conexion hace
      // que el anfitrion salude a una direccion que no existe para el juego, y el que llama se queda
      // en "conectando" para siempre haciendolo todo bien.
      //
      // Se acepta la que dice el cliente SOLO si es una IPv4 con forma de tal. Es un dato que el
      // descubrio preguntando al STUN y que yo no puedo ver desde aqui.
      const ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/;
      const mia = String(ip).replace(/^::ffff:/, '');
      const suya = String(b.ip || '').trim();
      const destino = ipv4.test(suya) ? suya : (ipv4.test(mia) ? mia : '');
      if (!destino) return responder(res, 400, { error: 'hace falta una direccion IPv4 (la que te dijo el STUN)' });
      s.llamadas = (s.llamadas || []).filter((l) => !(l.ip === destino && l.puerto === puerto));
      s.llamadas.push({ ip: destino, puerto, visto: Date.now() });
      if (s.llamadas.length > 32) s.llamadas.shift();
      if (!alcanzable(s)) return responder(res, 409, { error: 'esa sala no acepta gente de fuera' });
      // SIN CAMINO DIRECTO pero con puente: sin direccion, y el juego entra por el puente (Net.join_fuera)
      if (!directa(s)) return responder(res, 200, { ip: '', puerto: 0, puente: true, jugando: s.jugando === true, mapa: s.mapa });
      return responder(res, 200, {
        ip: s.pubIp || s.ip, puerto: s.pubPuerto || s.puerto,
        abierta: alcanzable(s), jugando: s.jugando === true, mapa: s.mapa,
      });
    }

    if (ruta === '/salas/cerrar' && req.method === 'POST') {
      const b = await leerCuerpo(req);
      const s = salas.get(String(b.id || ''));
      if (s && s.llave === String(b.llave || '')) { salas.delete(s.id); puente.cerrarSala(s.id); }
      return responder(res, 200, { ok: true });
    }

    // ---------------------------------------------------------------- registro
    if (ruta === '/registro' && req.method === 'POST') {
      const b = await leerCuerpo(req);
      const usuario = normalizarUsuario(b.usuario);
      if (!usuario) return responder(res, 400, { error: 'usuario: 3-16 letras, numeros, _ o -' });
      if (!claveValida(b.clave)) return responder(res, 400, { error: 'la clave necesita 6 caracteres o mas' });
      // EL CUPO SE CUENTA DESPUES DE VALIDAR. Estaba delante, y asi un usuario que se equivocaba tres
      // veces escribiendo (nombre corto, clave corta) gastaba su cupo de cuentas por hora sin haber
      // creado ninguna: acababa bloqueado por teclear mal. El limite esta para frenar a quien crea
      // cuentas de verdad, no a quien se equivoca.
      if (demasiado('reg:' + ip, 5, 3600000)) return responder(res, 429, { error: 'demasiadas cuentas desde aqui' });
      const sal = crypto.randomBytes(16).toString('hex');
      const cuenta = {
        usuario, nombre: String(b.nombre || b.usuario).slice(0, 16),
        sal, hash: hashClave(b.clave, sal),
        exp: 0, monedas: 0, armas: [], partidas: 0, ganadas: 0, nombre_elegido: true,
        creada: new Date().toISOString(), ultima: new Date().toISOString(), recientes: [],
      };
      // ifGenerationMatch=0 -> solo si NO existe. Es lo que hace el registro atomico: no hay
      // "comprobar y luego crear", que es donde se cuelan los duplicados.
      const gen = await escribir(objetoDe(usuario), cuenta, '0');
      if (gen === null) return responder(res, 409, { error: 'ese usuario ya existe' });
      // quien se registra con usuario y clave YA ha elegido un nombre unico (su propio usuario), asi
      // que no se le vuelve a preguntar. Se reserva para que nadie con Google se lo quite.
      await reservarNombre(cuenta.nombre, usuario);
      aCache(usuario, cuenta, gen);
      return responder(res, 200, { token: firmarToken(usuario), perfil: perfilPublico(cuenta) });
    }

    // ---------------------------------------------------------------- entrar
    if (ruta === '/entrar' && req.method === 'POST') {
      if (demasiado('ent:' + ip, 20, 600000)) return responder(res, 429, { error: 'demasiados intentos' });
      const b = await leerCuerpo(req);
      const usuario = normalizarUsuario(b.usuario);
      if (!usuario || !claveValida(b.clave)) return responder(res, 401, { error: 'usuario o clave incorrectos' });
      const c = await leer(objetoDe(usuario));
      // el mismo mensaje exista o no la cuenta: si no, se puede averiguar quien esta registrado
      if (!c) return responder(res, 401, { error: 'usuario o clave incorrectos' });
      if (!c.datos.hash || !igualesEnTiempoFijo(hashClave(b.clave, c.datos.sal), c.datos.hash))
        return responder(res, 401, { error: 'usuario o clave incorrectos' });
      if (c.datos.bloqueada)
        return responder(res, 403, { error: 'cuenta bloqueada' + (c.datos.motivo_bloqueo ? ': ' + c.datos.motivo_bloqueo : '') });
      aCache(usuario, c.datos, c.generacion);
      if (admin) await admin.cargarTodos(false);
      return responder(res, 200, { token: firmarToken(usuario), perfil: perfilPublico(c.datos) });
    }

    // ---------------------------------------------------------------- entrar con Google
    //
    // Flujo: el juego abre el navegador -> Google pregunta al usuario -> Google vuelve AQUI con un
    // codigo -> aqui se cambia el codigo por la identidad (con el secreto, que no sale del servidor)
    // -> se crea o se carga la cuenta -> se devuelve el navegador al juego con NUESTRO token.
    if (ruta === '/google/inicio') {
      if (!G_ID || !G_SECRET) return responder(res, 501, { error: 'el servidor no tiene configurado Google' });
      const puerto = parseInt(url.searchParams.get('puerto') || '0', 10);
      // `codigo`: por ahi recogera el juego su token cuando vuelva del navegador. Es el camino que
      // funciona en movil; el puerto se sigue admitiendo para no romper el PC.
      const codigo = String(url.searchParams.get('codigo') || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 32);
      if (!codigo && !(puerto > 1024 && puerto < 65536))
        return responder(res, 400, { error: 'hace falta un codigo o un puerto' });
      // `state` lleva el puerto del juego y va FIRMADO: si no, cualquiera podria hacer que el
      // navegador de un tercero acabase soltando un token en un puerto elegido por el atacante.
      const nonce = crypto.randomBytes(8).toString('hex');
      const dato = `${puerto}.${Date.now()}.${nonce}${codigo ? '-' + codigo : ''}`;
      const firma = crypto.createHmac('sha256', SECRETO).update(dato).digest('base64url');
      const state = `${dato}.${firma}`;
      const auth = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
        client_id: G_ID, redirect_uri: G_REDIR, response_type: 'code',
        scope: 'openid email profile', state, prompt: 'select_account',
      }).toString();
      res.writeHead(302, { Location: auth });
      return res.end();
    }

    if (ruta === '/google/callback') {
      const code = url.searchParams.get('code') || '';
      const state = url.searchParams.get('state') || '';
      const partes = state.split('.');
      if (partes.length !== 4) return paginaFin(res, null, 'respuesta de Google no valida');
      const [p0, t0, n0, f0] = partes;
      const cod = n0.includes('-') ? n0.split('-')[1] : '';
      const esperada = crypto.createHmac('sha256', SECRETO).update(`${p0}.${t0}.${n0}`).digest('base64url');
      if (!igualesEnTiempoFijo(f0, esperada)) return paginaFin(res, null, 'respuesta manipulada');
      if (Date.now() - parseInt(t0, 10) > 10 * 60000) return paginaFin(res, null, 'ha caducado, vuelve a intentarlo');
      if (!code) return paginaFin(res, null, 'Google no devolvio codigo');

      // el codigo se cambia por la identidad AQUI, con el secreto que nunca sale del servidor
      const tk = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ code, client_id: G_ID, client_secret: G_SECRET,
          redirect_uri: G_REDIR, grant_type: 'authorization_code' }).toString(),
      });
      if (!tk.ok) return paginaFin(res, null, 'Google rechazo el codigo');
      const jt = await tk.json();
      // el id_token es un JWT de Google: se lee el cuerpo, pero NO se confia en el sin verificar
      const cuerpoJwt = String(jt.id_token || '').split('.')[1] || '';
      let id = {};
      try { id = JSON.parse(Buffer.from(cuerpoJwt, 'base64url').toString('utf8')); } catch {}
      // VERIFICACION: se le pregunta a Google si ese id_token es suyo y para NOSOTROS. Sin comprobar
      // `aud`, valdria un token emitido para otra aplicacion cualquiera.
      const ver = await fetch('https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(jt.id_token || ''));
      if (!ver.ok) return paginaFin(res, null, 'no se pudo verificar la identidad');
      const vj = await ver.json();
      if (vj.aud !== G_ID || !vj.sub || vj.sub !== id.sub) return paginaFin(res, null, 'identidad no valida');

      const usuario = usuarioDeGoogle(vj.sub);
      const existente = await leer(objetoDe(usuario));
      if (!existente) {
        // CUENTA NUEVA, SIN FORMULARIO: es el "crear sesion automaticamente" que se pidio.
        const cuenta = {
          usuario, nombre: String(id.name || (vj.email || '').split('@')[0] || 'jugador').slice(0, 16),
          google: vj.sub, correo: String(vj.email || '').slice(0, 96),
          sal: '', hash: '',           // sin clave: a esta cuenta se entra solo con Google
          exp: 0, monedas: 0, armas: [], partidas: 0, ganadas: 0,
          // ENTRANDO CON GOOGLE NO SE ELIGE NOMBRE: se hereda el de la cuenta de Google, que no tiene
          // por que ser unico ni apetecible en una partida. El juego lo pedira antes del lobby.
          nombre_elegido: false,
          creada: new Date().toISOString(), ultima: new Date().toISOString(), recientes: [],
        };
        await escribir(objetoDe(usuario), cuenta, '0');
      } else if (existente.datos.bloqueada) {
        return paginaFin(res, null, 'cuenta bloqueada' + (existente.datos.motivo_bloqueo ? ': ' + existente.datos.motivo_bloqueo : ''));
      }
      const tokenFinal = firmarToken(usuario);
      if (cod) {
        limpiarRecoger();
        recoger.set(cod, { token: tokenFinal, hasta: Date.now() + RECOGER_MS });
      }
      return paginaFin(res, { token: tokenFinal, puerto: parseInt(p0, 10), codigo: cod }, '');
    }

    // ---------------------------------------------------------------- que sabe hacer este servidor
    if (ruta === '/config') {
      return responder(res, 200, { google: !!(G_ID && G_SECRET) });
    }

    // ---------------------------------------------------------------- perfil
    if (ruta === '/perfil') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      return responder(res, 200, { perfil: perfilPublico(c.datos) });
    }

    // ---------------------------------------------------------------- elegir nombre de jugador
    if (ruta === '/nombre' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const nombre = normalizarNombre(b.nombre);
      if (!nombre) return responder(res, 400, { error: 'de 3 a 16 letras o numeros, sin espacios dobles' });
      const anterior = c.datos.nombre_elegido ? c.datos.nombre : '';
      if (!(await reservarNombre(nombre, c.usuario)))
        return responder(res, 409, { error: 'ese nombre ya esta en uso, prueba otro' });
      const r = await actualizar(c.usuario, (cu) => {
        cu.nombre = nombre;
        cu.nombre_elegido = true;
        return { nombre };
      });
      if (r.error) {
        await soltarNombre(nombre);      // no se pudo guardar: se devuelve el nombre al bote
        return responder(res, 409, { error: r.error });
      }
      // el nombre viejo queda libre para otro (pero solo DESPUES de que el nuevo este guardado)
      if (anterior && anterior !== nombre) await soltarNombre(anterior);
      return responder(res, 200, { perfil: perfilPublico(r.cuenta) });
    }

    // ---------------------------------------------------------------- fin de partida
    if (ruta === '/partida' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const modo = String(b.modo || 'libre');
      const gano = b.gano === true;
      const seg = Math.max(0, Math.min(36000, parseInt(b.segundos || 0, 10) || 0));
      const datos = {
        oleada: Math.max(0, Math.min(50, parseInt(b.oleada || 0, 10) || 0)),
        bajas: Math.max(0, Math.min(500, parseInt(b.bajas || 0, 10) || 0)),
        puntos: Math.max(0, Math.min(100000, parseInt(b.puntos || 0, 10) || 0)),
        dano: Math.max(0, Math.min(100000, parseInt(b.dano || 0, 10) || 0)),
        objetivos: Math.max(0, Math.min(20, parseInt(b.objetivos || 0, 10) || 0)),
        mvp: b.mvp === true,
      };
      const r = await actualizar(c.usuario, (cu) => {
        const ahora = Date.now();
        cu.recientes = (cu.recientes || []).filter((t) => ahora - t < 3600000);
        if (cu.recientes.length >= PARTIDAS_POR_HORA) return { error: 'demasiadas partidas por hora' };
        cu.recientes.push(ahora);
        cu.partidas = (cu.partidas || 0) + 1;
        cu.ultima = new Date().toISOString();
        if (seg < SEGUNDOS_MINIMOS || !PREMIOS[modo] || modo === 'libre') return { exp: 0, oro: 0, motivo: 'partida demasiado corta' };
        if (gano) cu.ganadas = (cu.ganadas || 0) + 1;
        // PERDER TAMBIEN PAGA, a la mitad (antes perder no daba nada)
        // Con logros (duelo a muerte, bomba) la experiencia es la suma de lo que se ha hecho, validado aqui
        let p = PREMIOS[modo](datos);
        let logros = null;
        if (b.logros && (modo === 'dm' || modo === 'bomba')) {
          const lv = logrosValidos(b.logros, datos, gano);
          p = { exp: lv.exp };
          logros = lv.detalle;
        }
        const factor = gano ? 1 : MONEDAS.PERDER;
        const exp = Math.max(0, Math.min(TOPE_EXP, Math.floor(p.exp * factor)));
        const m = monedasDePartida(datos, gano);
        const oro = Math.max(0, Math.min(TOPE_ORO, m.oro));
        const n0 = nivelDe(cu.exp);
        cu.exp += exp; cu.monedas += oro;
        const misiones = avanzarMisiones(cu, modo, gano, datos, Date.now());
        return { exp, oro, detalle: m.detalle, misiones, subio: nivelDe(cu.exp) > n0, nivel: nivelDe(cu.exp),
          exp_antes: cu.exp - exp, logros, factor };
      });
      if (r.error) return responder(res, 429, { error: r.error });
      // EL TORNEO: los puntos de esta partida, si cuenta (torneos.js)
      let torneo = null;
      try { torneo = await torneos.partida(c.usuario, String(r.cuenta.nombre || c.usuario), nivelDe(r.cuenta.exp), b, gano, datos, seg); } catch (e) { console.error('[torneos] partida', e.message); }
      return responder(res, 200, { premio: r.extra, perfil: perfilPublico(r.cuenta), torneo });
    }

    // ---------------------------------------------------------------- equipo
    if (ruta === '/equipo' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('equipo:' + c.usuario, 60, 3600000)) return responder(res, 429, { error: 'demasiados cambios de equipo' });
      const b = await leerCuerpo(req);
      const eq = limpiarEquipo(b.equipo);
      if (!eq) return responder(res, 400, { error: 'equipo no valido' });
      const r = await actualizar(c.usuario, (cu) => { cu.equipo = eq; return { ok: true }; });
      if (r.error) return responder(res, 503, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta) });
    }

    // ---------------------------------------------------------------- pagos (desactivados)
    // LOS PACKS A LA VENTA, con su precio. Sin sesion: es un catalogo.
    if (ruta === '/pago/packs') {
      const precios = preciosPacks();
      const lista = Object.entries(PACKS).filter(([, p]) => !p.retirado).map(([id, p]) => ({
        id, creditos: p.creditos || 0, cubos: p.cubos || 0, unico: !!p.unico, precio: Number(precios[id]) || 0, moneda: MP_MONEDA,
        a_la_venta: !!MP_TOKEN && Number(precios[id]) > 0,
      }));
      return responder(res, 200, { packs: lista });
    }

    // Los pagos con dinero real estan desactivados en esta version.
    if (ruta === '/pago/crear' || ruta === '/pago/aviso' || ruta === '/pago/vuelta') {
      return responder(res, 410, { error: 'los pagos estan desactivados en esta version' });
    }

    // ---------------------------------------------------------------- la tienda / DINERO
    // EL ORO Y LOS CUBOS DE FUERZA CON DIAMANTES ({id}): lo que da y lo que cuesta es de CAMBIOS, no del juego
    if (ruta === '/tienda/cambio' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const id = String(b.id || '').slice(0, 24);
      const cam = Object.prototype.hasOwnProperty.call(CAMBIOS, id) ? CAMBIOS[id] : null;
      if (!cam) return responder(res, 400, { error: 'eso no esta a la venta' });
      const r = await actualizar(c.usuario, (cu) => {
        if ((cu.creditos || 0) < cam.creditos) return { error: 'no llegan los diamantes' };
        cu.creditos -= cam.creditos;
        if (cam.t === 'oro') cu.monedas = (cu.monedas || 0) + cam.n;
        else cu.cubos = (cu.cubos || 0) + cam.n;
        return { t: cam.t, n: cam.n };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), dado: r.extra });
    }
    // LO GRATIS ({que: "oro" | "cofre"}): 5 de oro cada 4 horas o un cofre comun cada 24 (ver GRATIS)
    if (ruta === '/tienda/gratis' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const que = b.que === 'cofre' ? 'cofre' : 'oro';
      const r = await actualizar(c.usuario, (cu) => {
        const ahora = Date.now();
        const falta = Math.ceil(gratisRestante(cu, que, ahora) / 60000);
        if (falta > 0) return { error: `todavia no: faltan ${falta >= 60 ? Math.floor(falta / 60) + ' h ' : ''}${falta % 60} min` };
        cu[GRATIS[que].campo] = ahora;
        if (que === 'oro') cu.monedas = (cu.monedas || 0) + ORO_GRATIS;
        else { cu.cofres = cu.cofres || []; cu.cofres.push(0); }
        return { que };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), dado: r.extra });
    }

    // ---------------------------------------------------------------- compra
    // ---------------------------------------------------------------- amigos
    // EL LATIDO NO LEE LA CUENTA: basta con el token (firmado) para saber quien es. Leerla cada minuto por
    // jugador conectado se habria comido las lecturas del mes. Devuelve los AVISOS pendientes (invitaciones de
    // amistad recien llegadas), solo si esta en el lobby: en partida se quedan para cuando vuelva.
    if (ruta === '/latido' && req.method === 'POST') {
      const cab = req.headers['authorization'] || '';
      const usuario = leerToken(cab.startsWith('Bearer ') ? cab.slice(7) : '');
      if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
      // BLOQUEADA desde el panel: el juego lo sabe en el siguiente latido (en memoria: no lee la cuenta)
      if (bloqueos.has(usuario)) return responderBloqueada(res, bloqueos.get(usuario));
      const enCache = deCache(usuario);
      if (enCache && enCache.datos.bloqueada) return responderBloqueada(res, enCache.datos.motivo_bloqueo);
      const b = await leerCuerpo(req);
      apuntarPresencia(usuario, b.donde);
      const refrescar = cambiadas.delete(usuario);
      let lista = [];
      if (b.donde !== 'partida' && avisos.has(usuario)) {
        lista = avisos.get(usuario).filter((a) => Date.now() - a.t < 600000).map((a) => a.ficha);
        avisos.delete(usuario);
      }
      // `rv`: la version de los regalos a todos (si cambia, el juego pide su perfil); `refrescar`: el panel toco la cuenta
      // `tv`: la version de los ajustes de la tienda (si cambia, el juego vuelve a pedir /tienda)
      // `espectar`: el panel pidio mirar una partida con esta cuenta (ver ESPECTAR)
      const orden = tomarOrdenEspectar(usuario, String(b.aparato || ''), b.donde === 'partida');
      return responder(res, 200, { ok: true, avisos: lista, refrescar, rv: admin.versionTodos(), tv: TIENDA.v,
        ...(orden ? { espectar: orden } : {}), ...equipos.latido(usuario) });
    }
    // ESPECTAR: la orden pendiente, al momento (el juego lo pregunta al abrirse o al volver al primer plano)
    if (ruta === '/espectar/pendiente' && req.method === 'POST') {
      const cab = req.headers['authorization'] || '';
      const usuario = leerToken(cab.startsWith('Bearer ') ? cab.slice(7) : '');
      if (!usuario) return responder(res, 401, { error: 'sesion no valida' });
      const bp = await leerCuerpo(req);
      return responder(res, 200, { espectar: tomarOrdenEspectar(usuario, String(bp.aparato || ''), bp.donde === 'partida') });
    }
    // ESPECTAR: lo pregunta el ANFITRION cuando alguien entra diciendo que es espectador. Sin sesion: el ticket va
    // firmado y dice para que sala es.
    if (ruta === '/espectar/verificar' && req.method === 'POST') {
      const b = await leerCuerpo(req);
      const d = leerTicketEspectar(b.ticket);
      if (!d || String(b.sala || '') !== d.s) return responder(res, 403, { error: 'ticket no valido' });
      const c = await cuentaAjena(d.u).catch(() => null);
      return responder(res, 200, { ok: true, usuario: d.u, nombre: (c && c.nombre) || d.u });
    }
    if (ruta.startsWith('/amigos')) {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (demasiado('ami:' + c.usuario, 60, 60000)) return responder(res, 429, { error: 'espera un momento' });
      apuntarPresencia(c.usuario, 'lobby');
      await asegurarId(c);
      if (ruta === '/amigos' && req.method === 'GET') return responder(res, 200, await listaAmigos(c));
      if (req.method !== 'POST') return responder(res, 404, { error: 'no existe' });
      const b = await leerCuerpo(req);
      if (ruta === '/amigos/buscar') {
        const u = await usuarioDeBusqueda(b.q);
        const a = u ? await cuentaAjena(u) : null;
        if (!a || !a.id_pub) return responder(res, 404, { error: 'no hay ningun jugador con ese apodo o ID' });
        const f = fichaAmigo(a, u);
        f.soy_yo = u === c.usuario;
        f.amigo = (c.datos.amigos || []).includes(u);
        f.invitado = (c.datos.sol_env || []).some((x) => x.a === u);
        return responder(res, 200, { jugador: f });
      }
      // el resto va por ID
      const otro = await usuarioDeBusqueda(String(b.id || ''));
      if (!otro) return responder(res, 404, { error: 'ese jugador no existe' });
      if (otro === c.usuario) return responder(res, 400, { error: 'no puedes invitarte a ti mismo' });
      const quitar = (lista, clave) => (lista || []).filter((x) => x[clave] !== otro);
      if (ruta === '/amigos/invitar') {
        const yo = c.datos;
        if ((yo.amigos || []).includes(otro)) return responder(res, 400, { error: 'ya sois amigos' });
        if ((yo.sol_env || []).some((x) => x.a === otro)) return responder(res, 400, { error: 'ya le has invitado' });
        // SI EL YA TE HABIA INVITADO, se acepta directamente
        if ((yo.sol_rec || []).some((x) => x.de === otro)) {
          const r1 = await actualizar(c.usuario, (cu) => {
            cu.sol_rec = (cu.sol_rec || []).filter((x) => x.de !== otro);
            if ((cu.amigos || []).length >= AMIGOS_MAX) return { error: 'tu lista de amigos esta llena' };
            cu.amigos = [...new Set([...(cu.amigos || []), otro])];
            return {};
          });
          if (r1.error) return responder(res, 400, { error: r1.error });
          await actualizar(otro, (cu) => {
            cu.sol_env = (cu.sol_env || []).filter((x) => x.a !== c.usuario);
            cu.amigos = [...new Set([...(cu.amigos || []), c.usuario])].slice(0, AMIGOS_MAX);
            return {};
          });
          c.datos = r1.cuenta;
          return responder(res, 200, Object.assign({ aceptada: true }, await listaAmigos(c)));
        }
        if ((yo.sol_env || []).length >= SOLICITUDES_MAX) return responder(res, 400, { error: 'tienes demasiadas invitaciones enviadas' });
        const r2 = await actualizar(otro, (cu) => {
          if ((cu.sol_rec || []).length >= SOLICITUDES_MAX) return { error: 'ese jugador tiene demasiadas invitaciones' };
          if ((cu.amigos || []).length >= AMIGOS_MAX) return { error: 'la lista de amigos de ese jugador esta llena' };
          cu.sol_rec = [...(cu.sol_rec || []).filter((x) => x.de !== c.usuario), { de: c.usuario, t: Date.now() }];
          return {};
        });
        if (r2.error) return responder(res, 400, { error: r2.error });
        const r3 = await actualizar(c.usuario, (cu) => {
          cu.sol_env = [...(cu.sol_env || []).filter((x) => x.a !== otro), { a: otro, t: Date.now() }];
          return {};
        });
        if (r3.cuenta) c.datos = r3.cuenta;
        avisar(otro, fichaAmigo(c.datos, c.usuario));
        return responder(res, 200, Object.assign({ enviada: true }, await listaAmigos(c)));
      }
      if (ruta === '/amigos/responder') {
        const acepta = b.aceptar === true;
        if (!(c.datos.sol_rec || []).some((x) => x.de === otro)) return responder(res, 400, { error: 'esa invitacion ya no esta' });
        const r1 = await actualizar(c.usuario, (cu) => {
          cu.sol_rec = quitar(cu.sol_rec, 'de');
          if (acepta) {
            if ((cu.amigos || []).length >= AMIGOS_MAX) return { error: 'tu lista de amigos esta llena' };
            cu.amigos = [...new Set([...(cu.amigos || []), otro])];
          }
          return {};
        });
        if (r1.error) return responder(res, 400, { error: r1.error });
        // en SU cuenta la invitacion es la que le mande YO: se busca por mi usuario, no por el suyo
        await actualizar(otro, (cu) => {
          cu.sol_env = (cu.sol_env || []).filter((x) => x.a !== c.usuario);
          if (acepta) cu.amigos = [...new Set([...(cu.amigos || []), c.usuario])].slice(0, AMIGOS_MAX);
          return {};
        });
        c.datos = r1.cuenta;
        return responder(res, 200, await listaAmigos(c));
      }
      if (ruta === '/amigos/cancelar') {
        const r1 = await actualizar(c.usuario, (cu) => { cu.sol_env = quitar(cu.sol_env, 'a'); return {}; });
        await actualizar(otro, (cu) => { cu.sol_rec = (cu.sol_rec || []).filter((x) => x.de !== c.usuario); return {}; });
        if (r1.cuenta) c.datos = r1.cuenta;
        return responder(res, 200, await listaAmigos(c));
      }
      if (ruta === '/amigos/quitar') {
        const r1 = await actualizar(c.usuario, (cu) => { cu.amigos = (cu.amigos || []).filter((u) => u !== otro); return {}; });
        await actualizar(otro, (cu) => { cu.amigos = (cu.amigos || []).filter((u) => u !== c.usuario); return {}; });
        if (r1.cuenta) c.datos = r1.cuenta;
        return responder(res, 200, await listaAmigos(c));
      }
      return responder(res, 404, { error: 'no existe' });
    }

    // LOS COFRES: abrir el primero de los pendientes (ver PROGRESO)
    if (ruta === '/cofre/abrir' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (!PROGRESO || !PROGRESO.cofres) return responder(res, 503, { error: 'los cofres no estan disponibles' });
      const r = await actualizar(c.usuario, (cu) => {
        if (!Array.isArray(cu.cofres) || !cu.cofres.length) return { error: 'no tienes cofres por abrir' };
        const inicio = parseInt(cu.cofres.shift(), 10) || 0;
        const resultado = sortearCofre(cu, inicio);
        darPremioCofre(cu, resultado.premio);
        return { resultado };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      const resultado = (r.extra && r.extra.resultado) || null;
      console.log('[cofre]', c.usuario, resultado && resultado.rareza, resultado && JSON.stringify(resultado.premio));
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), resultado });
    }
    // SUBIR DE NIVEL UNA CARTA: gasta sus copias y oro (ver PROGRESO.cofres.cartas y scripts/cartas.gd)
    if (ruta === '/carta/mejorar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const tc = PROGRESO && PROGRESO.cofres && PROGRESO.cofres.cartas;
      if (!tc) return responder(res, 503, { error: 'no disponible' });
      const b = await leerCuerpo(req);
      const id = String(b.id || '').slice(0, 32);
      if (!tc.ids.includes(id)) return responder(res, 400, { error: 'esa carta no existe' });
      const r = await actualizar(c.usuario, (cu) => {
        const e = (cu.cartas || {})[id];
        if (!e || !e.n) return { error: 'no tienes esa carta' };
        if (e.n >= tc.nivel_max) return { error: 'ya esta al maximo' };
        const copias = ajJuego('cartas_copias', tc.copias)[e.n];     // el panel puede cambiarlos (JUEGO)
        const oro = ajJuego('cartas_oro', tc.oro)[e.n];
        // y CUBOS DE FUERZA (2026-09-30, pedido: "cubos de fuerza y dinero, no diamantes")
        const cubos = ajJuego('cartas_cubos', tc.cubos || CARTAS_CUBOS_FABRICA)[e.n] || 0;
        if ((e.c || 0) < copias) return { error: 'faltan copias' };
        if ((cu.cubos || 0) < cubos) return { error: 'no llegan los cubos de fuerza' };
        if ((cu.monedas || 0) < oro) return { error: 'no llega el oro' };
        cu.cubos = (cu.cubos || 0) - cubos;
        cu.monedas -= oro;
        e.c -= copias;
        e.n += 1;
        cu.cartas[id] = e;
        return { nivel: e.n };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta) });
    }
    // SUBIR DE NIVEL UN PERSONAJE: cubos de fuerza + oro (ver PROGRESO.personajes)
    if (ruta === '/personaje/mejorar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const t = PROGRESO && PROGRESO.personajes;
      if (!t) return responder(res, 503, { error: 'no disponible' });
      const b = await leerCuerpo(req);
      const nombre = String(b.nombre || '').slice(0, 32);
      if (!t.nombres.includes(nombre)) return responder(res, 400, { error: 'ese personaje no existe' });
      const r = await actualizar(c.usuario, (cu) => {
        // el personaje es tuyo si es de todos o si tienes alguna de sus skins (PROGRESO.personajes.skins)
        const suyo = t.gratis.includes(nombre) || ((t.skins && t.skins[nombre]) || []).some((sk) => (cu.armas || []).includes('modelo:' + sk));
        if (!suyo) return { error: 'ese personaje no es tuyo' };
        cu.personajes = cu.personajes || {};
        const n = Math.max(1, parseInt(cu.personajes[nombre], 10) || 1);
        if (n >= t.max) return { error: 'ya esta al maximo' };
        const [cubos, oro] = ajJuego('personajes_coste', t.coste)[String(n + 1)];
        if ((cu.cubos || 0) < cubos) return { error: 'no llegan los cubos de fuerza' };
        if ((cu.monedas || 0) < oro) return { error: 'no llega el oro' };
        cu.cubos -= cubos;
        cu.monedas -= oro;
        cu.personajes[nombre] = n + 1;
        return { nivel: n + 1 };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta) });
    }
    // LAS TAREAS: reclamar una cumplida ({id}) o todas ({id: ""}). Da la EXPERIENCIA de cada una.
    if (ruta === '/mision/reclamar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const id = String(b.id || '').slice(0, 24);
      const ahora = Date.now();
      const r = await actualizar(c.usuario, (cu) => {
        const st = estadoMisiones(cu, ahora);
        let exp = 0;
        const cobrar = (lista, prog) => {
          for (const m of lista) {
            const p = prog[m.id];
            if (!p || !p.hecha || p.cobrada || (id && m.id !== id)) continue;
            p.cobrada = true;
            exp += m.premio;
          }
        };
        cobrar(elegirMisiones(MISIONES_DIARIAS, DIARIAS_POR_DIA, st.dia), st.d);
        cobrar(elegirMisiones(MISIONES_SEMANALES, SEMANALES_POR_SEMANA, st.sem), st.s);
        if (!exp) return { error: 'no hay tareas que reclamar' };
        cu.misiones = { dia: st.dia, sem: st.sem, d: st.d, s: st.s };
        const n0 = nivelDe(cu.exp);
        cu.exp = (cu.exp || 0) + exp;
        if (PASE) {
          cu.pase_exp = cu.pase_exp || {};
          const tp = 't' + temporadaPase();
          cu.pase_exp[tp] = (cu.pase_exp[tp] || 0) + exp;
        }
        return { exp, subio: nivelDe(cu.exp) > n0 };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), exp: (r.extra && r.extra.exp) || 0 });
    }

    // EL PASE DE BATALLA: reclamar lo de un nivel ya alcanzado (ver PASE)
    if (ruta === '/camino/reclamar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (!CAMINO || !Array.isArray(CAMINO.niveles)) return responder(res, 503, { error: 'el camino no esta disponible' });
      const r = await actualizar(c.usuario, (cu) => {
        const nv = nivelDe(cu.exp);
        cu.camino = Array.isArray(cu.camino) ? cu.camino : [];
        const niveles = [], dado = [];
        for (const d of CAMINO.niveles) {
          if (d.nivel > nv || cu.camino.includes(d.nivel)) continue;
          cu.camino.push(d.nivel);
          niveles.push(d.nivel);
          dado.push(darDelCamino(cu, d.c));
        }
        if (!niveles.length) return { ya: true };
        return { niveles, dado };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      const ex = r.extra || {};
      if (ex.niveles && ex.niveles.length) console.log('[camino]', c.usuario, ex.niveles.join(','), (ex.dado || []).join(', '));
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), niveles: ex.niveles || [], dado: ex.dado || [] });
    }

    if (ruta === '/pase/reclamar' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      if (!PASE || !Array.isArray(PASE.niveles)) return responder(res, 503, { error: 'el pase no esta disponible' });
      const b = await leerCuerpo(req);
      const n = parseInt(b.nivel, 10);
      const fila = b.fila === 'p' ? 'p' : 'g';
      if (!paseCfg().activo) return responder(res, 400, { error: 'el pase esta desactivado' });
      if (b.temporada !== undefined && parseInt(b.temporada, 10) !== temporadaPase()) return responder(res, 400, { error: 'esa temporada ya termino' });
      const d = ajJuego('pase_niveles', PASE.niveles).find((x) => x.nivel === n);
      if (!d || !Array.isArray(d[fila]) || !d[fila].length) return responder(res, 400, { error: 'ese nivel no existe' });
      const t = 't' + temporadaPase();
      const r = await actualizar(c.usuario, (cu) => {
        if (nivelPase(cu) < n) return { error: `te falta llegar al nivel ${n} del pase` };
        if (fila === 'p' && !(cu.armas || []).includes(clavePremium())) return { error: 'hace falta el pase premium' };
        cu.pase = cu.pase || {};
        cu.pase[t] = cu.pase[t] || { g: [], p: [] };
        cu.pase[t][fila] = cu.pase[t][fila] || [];
        if (cu.pase[t][fila].includes(n)) return { ya: true };
        cu.pase[t][fila].push(n);
        const dado = d[fila].map((x) => darDelPase(cu, x)).filter(Boolean);
        return { dado };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      console.log('[pase]', c.usuario, fila, n, (r.extra && r.extra.dado || []).join(', '));
      return responder(res, 200, { perfil: perfilPublico(r.cuenta), dado: (r.extra && r.extra.dado) || [] });
    }

    if (ruta === '/compra' && req.method === 'POST') {
      const c = await cuentaDeToken(req);
      if (!c) return responder(res, 401, { error: 'sesion no valida' });
      const b = await leerCuerpo(req);
      const arma = String(b.arma || '').slice(0, 48);
      // EL PRECIO ES EL DE LA LISTA, no el que mande el juego (que se ignora)
      // el premium del pase: solo el de la temporada en curso y con el pase encendido (pase_config del panel)
      if (/^pase_t\d+$/.test(arma) && (arma !== clavePremium() || !paseCfg().activo)) return responder(res, 400, { error: 'ese pase ya no esta a la venta' });
      if (!Object.prototype.hasOwnProperty.call(PRECIOS, arma) && arma !== clavePremium()) return responder(res, 400, { error: 'eso no esta a la venta' });
      // BLOQUEADO DESDE EL PANEL (o la skin de un personaje bloqueado): no se cobra
      const pjDeSkin = arma.startsWith('modelo:') ? Object.entries((PROGRESO && PROGRESO.personajes && PROGRESO.personajes.skins) || {})
        .find(([, l]) => Array.isArray(l) && l.includes(arma.slice(7))) : null;
      if (bloqueado('articulos', arma) || (pjDeSkin && bloqueado('personajes', pjDeSkin[0]))) {
        return responder(res, 400, { error: 'eso esta en mantenimiento' });
      }
      const precio = precioDe(arma);        // el del panel si lo cambio (cargarTienda)
      // CON QUE SE PAGA. "monedas" (las de jugar, precio entero) o "creditos" (los de dinero real, con
      // un 25 % menos). El descuento lo calcula el SERVIDOR a partir del precio: si lo mandara el
      // cliente ya descontado, cualquiera se ponia el descuento que quisiera.
      const moneda = b.moneda === 'creditos' ? 'creditos' : 'monedas';
      // EL PREMIUM DEL PASE ("pase_...") y LO QUE SOLO SE VENDE CON DIAMANTES (el catalogo del juego lo marca con
      // moneda "creditos": el PUÑO DE ORO, 2026-09-30): solo con diamantes y sin descuento (su precio ya esta en diamantes)
      const esPase = arma.startsWith('pase_');
      const soloDiamantes = esPase || (CATALOGO[arma] && CATALOGO[arma].moneda === 'creditos');
      if (soloDiamantes && moneda !== 'creditos') {
        return responder(res, 400, { error: esPase ? 'el pase premium se paga con diamantes' : 'eso solo se compra con diamantes' });
      }
      let coste = soloDiamantes ? precio : (moneda === 'creditos' ? precioConCreditos(precio) : precio);
      // LOS DESTACADOS DEL PANEL: su precio y su moneda, sin descuentos (ver LOS AJUSTES DEL JUEGO). Lo que solo va con
      // diamantes no se cobra en oro aunque el panel lo destaque asi.
      const dest = (TIENDA.destacados || []).find((d) => d.clave === arma);
      let monedaPago = moneda;
      if (dest && !(soloDiamantes && dest.moneda !== 'creditos')) { coste = dest.precio; monedaPago = dest.moneda; }
      if (!arma) return responder(res, 400, { error: 'falta el arma' });
      const r = await actualizar(c.usuario, (cu) => {
        cu.armas = cu.armas || [];
        if (cu.armas.includes(arma)) return { ya: true };
        const saldo = monedaPago === 'creditos' ? (cu.creditos || 0) : cu.monedas;
        if (saldo < coste) return { error: monedaPago === 'creditos' ? 'no llegan los creditos' : 'no llega el dinero' };
        if (monedaPago === 'creditos') cu.creditos = saldo - coste; else cu.monedas -= coste;
        cu.armas.push(arma);
        return { comprada: arma };
      });
      if (r.error) return responder(res, 400, { error: r.error });
      return responder(res, 200, { perfil: perfilPublico(r.cuenta) });
    }

    return responder(res, 404, { error: 'no existe' });
  } catch (e) {
    // la cuenta de la sesion esta BLOQUEADA (cuentaDeToken): se dice, para que el juego enseñe el cartel
    if (e && e.bloqueada) return responderBloqueada(res, e.motivo);
    // nunca se devuelve el detalle del error al cliente: filtra nombres de bucket y rutas internas
    console.error('[error]', ruta, e && e.message);
    return responder(res, 500, { error: 'error del servidor' });
  }
});

servidor.keepAliveTimeout = 65000;    // por encima del balanceador de Cloud Run: evita cortes a medias
servidor.on('upgrade', (req, socket, cabeza) => {
  puente.upgrade(req, socket, cabeza).catch((e) => { console.error('[puente]', e && e.message); socket.destroy(); });
});
servidor.listen(PUERTO, () => console.log(`breach-cuentas escuchando en ${PUERTO} · ${LOCAL ? 'LOCAL ' + LOCAL : 'bucket ' + BUCKET}`));
cargarTienda();
