"""TERRENO del mapa "isla": mapa de alturas a 15 cm + material de cada columna.

No se dibuja con primitivas (serian millones de cajas): es un campo de alturas H(x, z) en metros, uno por
columna de voxels, y tres mapas de material por columna (la piel de arriba, lo de debajo y lo hondo). El
rasterizador lo convierte en voxels baldosa a baldosa (`volumen`) y ENCIMA aplica las primitivas.

Pasos (en este orden, cada uno sobre lo anterior):
  1. `base`: silueta de la isla (radio de costa con ruido), playa, fondo del mar, y el relieve de cada region
     (montanas con cresta, dunas y mesetas, colinas del bosque, la llanura del amazonas).
  2. Lo que piden las zonas: `aplanar` (parcelas de edificios y plazas), `pintar` (calles de la ciudad,
     plazas), `excavar` (lagos, fosos).
  3. `finalizar`: carreteras (perfil suavizado con pendiente maxima), rio, lago, oasis, y los materiales.

TODO EL TERRENO ES ANCLA (tipos "suelo" y "suelo_duro" del lienzo): un edificio que apoya en el terreno no se
cae aunque le vuelen la planta baja entera, y el monte no se derrumba: se le hacen crateres.

La piel de arriba tiene DOS voxels: en una ladera cada escalon de un voxel ensena su contrahuella, y con un
solo voxel de cesped encima las laderas salian rayadas de tierra.
"""
import math
import numpy as np
from scipy import ndimage

import disposicion as D

VS = D.VOXEL
N = int(round(D.ANCHO_X / VS))           # 3328 columnas por lado
PIEL = 2                                 # voxels de material de superficie
SUB = 4                                  # voxels de subsuelo por debajo de la piel


def _ss(a, b, x):
    """smoothstep que admite a > b (bajada)"""
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Terreno:
    def __init__(self, semilla):
        self.rng = np.random.default_rng(semilla)
        c = ((np.arange(N, dtype=np.float32) + 0.5) * VS)
        self.X = np.broadcast_to(c[:, None], (N, N))       # [ix, iz]
        self.Z = np.broadcast_to(c[None, :], (N, N))
        self.H = None
        self.mats = []                                     # nombres; los mapas guardan indices
        self.piel = None
        self.sub = None
        self.hondo = None
        self.bandas = None                                  # columnas con estratos (mesetas)
        self.bioma = None                                   # 0 costa 1 ciudad 2 monte 3 bosque 4 desierto 5 selva
        self.pintados = []                                  # (tipo, datos, material)
        self.aplanados = []
        self.excavados = []
        self.macizos = []                                   # rectangulos que no se vacian por dentro (tuneles, bunkeres)
        self.ocupado = np.zeros((int(D.ANCHO_X), int(D.ANCHO_Z)), bool)   # rejilla de 1 m: donde no plantar

    # ------------------------------------------------------------------ utilidades
    def m(self, nombre):
        if nombre not in self.mats:
            self.mats.append(nombre)
        return self.mats.index(nombre)

    def ruido(self, escala_m, octavas=1, persist=0.5):
        """ruido de valor suave en [0, 1] sobre toda la rejilla (escala = tamano de la mancha en metros)"""
        total = np.zeros((N, N), np.float32)
        amp, suma, esc = 1.0, 0.0, escala_m
        for _ in range(octavas):
            n = max(3, int(D.ANCHO_X / esc) + 2)
            g = self.rng.random((n, n), dtype=np.float32)
            z = ndimage.zoom(g, N / (n - 1.0), order=3, mode="nearest")
            total += amp * z[:N, :N]
            suma += amp
            amp *= persist
            esc *= 0.5
        return np.clip(total / suma, 0.0, 1.0)

    def _ij(self, x, z):
        return (min(N - 1, max(0, int(x / VS))), min(N - 1, max(0, int(z / VS))))

    def _ventana(self, x0, z0, x1, z1):
        i0, k0 = self._ij(x0, z0)
        i1, k1 = self._ij(x1, z1)
        return slice(i0, i1 + 1), slice(k0, k1 + 1)

    # ------------------------------------------------------------------ consultas (para las zonas)
    def altura(self, x, z):
        """cota del suelo en ese punto (multiplo de voxel: lo que de verdad se pisa)"""
        i, k = self._ij(x, z)
        return round(float(self.H[i, k]) / VS) * VS

    def altura_min(self, x0, z0, x1, z1):
        sx, sz = self._ventana(x0, z0, x1, z1)
        return round(float(self.H[sx, sz].min()) / VS) * VS

    def altura_max(self, x0, z0, x1, z1):
        sx, sz = self._ventana(x0, z0, x1, z1)
        return round(float(self.H[sx, sz].max()) / VS) * VS

    def pendiente(self, x, z, r=2.0):
        return (self.altura_max(x - r, z - r, x + r, z + r) - self.altura_min(x - r, z - r, x + r, z + r)) / (2 * r)

    def bioma_de(self, x, z):
        i, k = self._ij(x, z)
        return int(self.bioma[i, k])

    def en_tierra(self, x, z, margen=0.8):
        return self.altura(x, z) > D.MAR_Y + margen

    def ocupar(self, x0, z0, x1, z1):
        a0, b0 = max(0, int(min(x0, x1))), max(0, int(min(z0, z1)))
        a1, b1 = min(self.ocupado.shape[0], int(math.ceil(max(x0, x1)))), min(self.ocupado.shape[1], int(math.ceil(max(z0, z1))))
        self.ocupado[a0:a1, b0:b1] = True

    def libre(self, x0, z0, x1, z1):
        a0, b0 = max(0, int(min(x0, x1))), max(0, int(min(z0, z1)))
        a1, b1 = min(self.ocupado.shape[0], int(math.ceil(max(x0, x1)))), min(self.ocupado.shape[1], int(math.ceil(max(z0, z1))))
        return not self.ocupado[a0:a1, b0:b1].any()

    # ------------------------------------------------------------------ peticiones de las zonas
    def aplanar(self, x0, z0, x1, z1, y, falda=6.0, mat=None):
        """Parcela plana a cota `y` con una falda de `falda` metros que empalma con lo de alrededor."""
        self.aplanados.append((min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1), D.q(y), falda, mat))

    def pintar(self, x0, z0, x1, z1, mat):
        self.pintados.append(("rect", (min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1)), mat))

    def pintar_disco(self, cx, cz, r, mat):
        self.pintados.append(("disco", (cx, cz, r), mat))

    def macizo(self, x0, z0, x1, z1):
        """Que el monte no se vacie por dentro aqui (ver `volumen`): tuneles y bunkeres excavados."""
        self.macizos.append((min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1)))

    def excavar(self, cx, cz, rx, rz, fondo):
        self.excavados.append((cx, cz, rx, rz, fondo))

    # ------------------------------------------------------------------ 1. el relieve
    def base(self):
        X, Z = self.X, self.Z
        dx, dz = X - D.CX, Z - D.CZ
        r = np.hypot(dx, dz)
        th = np.arctan2(dz, dx)
        # la costa: un radio con ondulaciones de varias frecuencias y ruido fino
        rc = (D.COSTA_R + 11.0 * np.sin(3 * th + 0.7) + 8.0 * np.sin(5 * th + 2.1) + 5.0 * np.sin(9 * th + 0.3)
              + 3.0 * np.sin(17 * th + 1.3))
        rc = rc + (self.ruido(40.0, 3) - 0.5) * 16.0
        # el puerto: una bahia al sureste, abrigada (la costa entra 20 m)
        ang_p = math.atan2(D.PUERTO[1] - D.CZ, D.PUERTO[0] - D.CX)
        dang = np.abs(np.angle(np.exp(1j * (th - ang_p))))
        rc = rc - 18.0 * _ss(0.16, 0.0, dang)
        d = rc - r                                         # >0 tierra adentro
        self.dcosta = d.astype(np.float32)
        suave = self.ruido(70.0, 3)
        H = np.where(d < 0,
                     D.MAR_Y - 0.25 - 2.3 * _ss(0.0, 22.0, -d),
                     D.MAR_Y - 0.25 + 0.9 * _ss(0.0, 12.0, d) + 0.85 * _ss(8.0, 50.0, d)
                     + (suave - 0.5) * 0.6 * _ss(20.0, 60.0, d)).astype(np.float32)
        tierra = _ss(4.0, 30.0, d)

        # --- pesos de region --------------------------------------------------------------------------
        cheb = np.maximum(np.abs(dx), np.abs(dz))
        w_ciudad = _ss(96.0, 80.0, cheb)
        mx0, mx1 = 112.0, 424.0
        w_monte = (_ss(150.0, 112.0, Z) * _ss(52.0, 82.0, Z) * _ss(mx0, mx0 + 55.0, X) * _ss(mx1, mx1 - 60.0, X)).astype(np.float32)

        def gauss(c, rad):
            return np.exp(-((X - c[0]) ** 2 + (Z - c[1]) ** 2) / (2 * (rad * 0.62) ** 2)).astype(np.float32)
        w_bosque = gauss(D.BOSQUE, D.BOSQUE[2])
        w_des = gauss(D.DESIERTO, D.DESIERTO[2])
        w_selva = gauss(D.AMAZONAS, D.AMAZONAS[2])

        # --- MONTANAS: cresta con picos (ruido "ridged") y la cumbre del observatorio --------------------
        # picos gaussianos a lo largo de la cresta + ruido "ridged" que les da aristas y canales
        rid = 1.0 - np.abs(2.0 * self.ruido(38.0, 4, 0.55) - 1.0)
        picos = np.zeros_like(H)
        for px, pz, pr, pa in D.PICOS:
            picos = np.maximum(picos, pa * np.exp(-((X - px) ** 2 + ((Z - pz) * 1.25) ** 2) / (2 * pr ** 2)))
        monte = w_monte * (4.0 + picos * (0.60 + 0.45 * rid) + 4.0 * rid)
        H = H + monte * tierra
        self.monte = monte

        # --- BOSQUE: colinas suaves ---------------------------------------------------------------------
        col = self.ruido(45.0, 3)
        H = H + w_bosque * tierra * (col * 7.0) * (1.0 - w_monte)

        # --- DESIERTO: dunas (ondas deformadas con cresta afilada) y mesetas -----------------------------
        warp = (self.ruido(60.0, 2) - 0.5) * 30.0
        u = (X * 0.8 + Z * 0.6 + warp) / 17.0
        duna = (0.5 + 0.5 * np.sin(u * math.tau)) ** 2.2
        duna = duna * (0.6 + 0.8 * self.ruido(50.0, 2))
        H = H + w_des * tierra * duna * 3.2 * (1.0 - w_ciudad)
        self.bandas = np.zeros((N, N), bool)
        for cx, cz, rad, alto in D.MESETAS:
            dm = np.hypot(X - cx, Z - cz) + (self.ruido(12.0, 2) - 0.5) * 7.0
            k = _ss(rad + 2.5, rad - 1.0, dm)           # acantilado casi vertical
            base = H.copy()
            cima = D.q(float(np.median(base[self._ventana(cx - 2, cz - 2, cx + 2, cz + 2)])) + alto)
            H = np.where(k > 0.0, np.maximum(H, base + (cima - base) * k), H)
            self.bandas |= (dm < rad + 3.0)

        # --- AMAZONAS: llanura baja y humeda ------------------------------------------------------------
        llano = D.MAR_Y + 0.9 + self.ruido(30.0, 2) * 0.7
        H = np.where(d > 0, H + (llano - H) * w_selva * 0.85 * (1.0 - w_monte), H)

        # --- CIUDAD: la meseta de la ciudad, plana a su cota ---------------------------------------------
        H = H + (D.COTA_CIUDAD - H) * w_ciudad * tierra

        self.H = H.astype(np.float32)
        # regiones para materiales y vegetacion (con ruido en las fronteras)
        rb = (self.ruido(25.0, 2) - 0.5) * 0.5
        pesos = np.stack([np.full_like(H, 0.12), w_ciudad * 2.0, w_monte * 1.6 + 0.001, w_bosque + rb * 0.4,
                          w_des + rb * 0.3, w_selva - rb * 0.3])
        self.bioma = np.argmax(pesos, axis=0).astype(np.uint8)
        del pesos
        self.bioma[d < 14.0] = 0
        self.w_monte = w_monte
        self.w_des = w_des

    # ------------------------------------------------------------------ 3. carreteras, agua, materiales
    def _aplicar_aplanados(self):
        for x0, z0, x1, z1, y, falda, _mat in self.aplanados:
            sx, sz = self._ventana(x0 - falda, z0 - falda, x1 + falda, z1 + falda)
            X, Z = self.X[sx, sz], self.Z[sx, sz]
            ex = np.maximum(np.maximum(x0 - X, X - x1), 0.0)
            ez = np.maximum(np.maximum(z0 - Z, Z - z1), 0.0)
            w = _ss(falda, 0.0, np.hypot(ex, ez)) if falda > 0 else ((ex == 0) & (ez == 0)).astype(np.float32)
            self.H[sx, sz] = self.H[sx, sz] + (y - self.H[sx, sz]) * w

    def _perfil(self, pts, paso=1.5, pendiente=0.09, ventana=24.0):
        """Muestrea la polilinea, suaviza la altura y la limita en pendiente. Devuelve (xs, zs, ys, s)."""
        xs, zs, ss = [], [], []
        acum = 0.0
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            L = math.hypot(bx - ax, bz - az)
            n = max(1, int(L / paso))
            for i in range(n):
                t = i / n
                xs.append(ax + (bx - ax) * t)
                zs.append(az + (bz - az) * t)
                ss.append(acum + L * t)
            acum += L
        xs.append(pts[-1][0]); zs.append(pts[-1][1]); ss.append(acum)
        ys = np.array([float(self.H[self._ij(x, z)]) for x, z in zip(xs, zs)])
        ys = np.maximum(ys, D.MAR_Y + 0.9)                  # una carretera nunca va bajo el agua
        k = max(1, int(ventana / paso))
        ker = np.ones(2 * k + 1) / (2 * k + 1)
        pad = np.pad(ys, k, mode="edge")
        ys = np.convolve(pad, ker, mode="valid")
        dmax = pendiente * paso
        for i in range(1, len(ys)):
            ys[i] = min(max(ys[i], ys[i - 1] - dmax), ys[i - 1] + dmax)
        for i in range(len(ys) - 2, -1, -1):
            ys[i] = min(max(ys[i], ys[i + 1] - dmax), ys[i + 1] + dmax)
        return np.array(xs), np.array(zs), ys, np.array(ss)

    def _carretera(self, pts, ancho, mat, falda=7.0, lineas=True, bordes_de_ciudad=False):
        xs, zs, ys, _ss_ = self._perfil(pts)
        self.perfiles.append((pts, xs, zs, ys, ancho))
        med = ancho * 0.5
        for i in range(len(xs) - 1):
            ax, az, bx, bz = xs[i], zs[i], xs[i + 1], zs[i + 1]
            sx, sz = self._ventana(min(ax, bx) - med - falda, min(az, bz) - med - falda,
                                   max(ax, bx) + med + falda, max(az, bz) + med + falda)
            X, Z = self.X[sx, sz], self.Z[sx, sz]
            ddx, ddz = bx - ax, bz - az
            l2 = ddx * ddx + ddz * ddz or 1e-9
            t = np.clip(((X - ax) * ddx + (Z - az) * ddz) / l2, 0.0, 1.0)
            dist = np.hypot(X - ax - ddx * t, Z - az - ddz * t)
            y = ys[i] + (ys[i + 1] - ys[i]) * t
            y = np.round(y / VS) * VS
            w = _ss(med + falda, med + 0.6, dist)
            mejor = w > self._w_carr[sx, sz]
            self.H[sx, sz] = np.where(mejor, self.H[sx, sz] + (y - self.H[sx, sz]) * w, self.H[sx, sz])
            self._w_carr[sx, sz] = np.maximum(self._w_carr[sx, sz], w)
            calzada = dist <= med
            self._mat_carr[sx, sz] = np.where(calzada, self.m(mat), self._mat_carr[sx, sz])
            arcen = (dist > med) & (dist <= med + 0.9) & (self._mat_carr[sx, sz] == 255)
            self._mat_carr[sx, sz] = np.where(arcen, self.m("grava"), self._mat_carr[sx, sz])
            if lineas and mat == "asfalto":
                # linea central discontinua (3 m si, 3 m no) y lineas de borde continuas
                s = np.hypot(X - ax, Z - az)
                # SOLO EL EJE AMARILLO. Las lineas blancas de borde iban por los dos lados de cada
                # carretera del mapa entero y el resultado era una isla rayada de blanco por todas
                # partes; quitandolas, el asfalto se lee como asfalto.
                cent = (dist <= 0.08) & (((s + i * 1.5) % 6.0) < 3.0)
                self._pint_carr[sx, sz] = np.where(cent, self.m("linea_amarilla"), self._pint_carr[sx, sz])

    def finalizar(self):
        self._aplicar_aplanados()
        self._w_carr = np.zeros((N, N), np.float32)
        self._mat_carr = np.full((N, N), 255, np.uint8)
        self._pint_carr = np.full((N, N), 255, np.uint8)
        self.perfiles = []
        for _n, pts, ancho, mat in D.CARRETERAS:
            self._carretera(pts, ancho, mat)
        # --- AGUA: rio, lago, oasis y lo que pidan las zonas. El lecho por debajo del mar: el agua es el mar.
        X, Z = self.X, self.Z
        for (ax, az), (bx, bz) in zip(D.RIO, D.RIO[1:]):
            med = D.RIO_ANCHO * 0.5
            sx, sz = self._ventana(min(ax, bx) - med - 8, min(az, bz) - med - 8, max(ax, bx) + med + 8, max(az, bz) + med + 8)
            Xs, Zs = X[sx, sz], Z[sx, sz]
            ddx, ddz = bx - ax, bz - az
            l2 = ddx * ddx + ddz * ddz or 1e-9
            t = np.clip(((Xs - ax) * ddx + (Zs - az) * ddz) / l2, 0.0, 1.0)
            dist = np.hypot(Xs - ax - ddx * t, Zs - az - ddz * t)
            fondo = D.RIO_LECHO + (D.MAR_Y + 0.4 - D.RIO_LECHO) * _ss(med * 0.55, med + 3.0, dist)
            self.H[sx, sz] = np.minimum(self.H[sx, sz], np.where(dist < med + 3.0, fondo, 99.0))
        for cx, cz, rx, rz, fondo in [D.LAGO + (1.0,), D.OASIS + (1.6,)] + self.excavados:
            sx, sz = self._ventana(cx - rx - 8, cz - rz - 8, cx + rx + 8, cz + rz + 8)
            e = np.hypot((X[sx, sz] - cx) / rx, (Z[sx, sz] - cz) / rz)
            e = e + (self.ruido_local(e.shape, 6.0) - 0.5) * 0.25
            prof = fondo + (D.MAR_Y + 0.5 - fondo) * _ss(0.55, 1.25, e)
            self.H[sx, sz] = np.minimum(self.H[sx, sz], np.where(e < 1.25, prof, 99.0))
        self.H = np.clip(self.H, D.BASE_Y + 0.3, D.ALTO_MUNDO - 6.0)
        self.H = (np.round(self.H / VS) * VS).astype(np.float32)
        self._materiales()

    def ruido_local(self, forma, escala_px):
        g = self.rng.random((int(forma[0] / escala_px) + 3, int(forma[1] / escala_px) + 3), dtype=np.float32)
        z = ndimage.zoom(g, (forma[0] / (g.shape[0] - 3), forma[1] / (g.shape[1] - 3)), order=1)
        return z[:forma[0], :forma[1]]

    def _materiales(self):
        H, B = self.H, self.bioma
        m = self.m
        # pendiente local (m por m) con el gradiente sobre 1,2 m
        gx, gz = np.gradient(ndimage.uniform_filter(H, 5), VS)
        pend = np.hypot(gx, gz)
        mancha = self.ruido(14.0, 2)
        piel = np.full(H.shape, m("cesped"), np.uint8)
        sub = np.full(H.shape, m("tierra"), np.uint8)
        hondo = np.full(H.shape, m("roca_monte"), np.uint8)
        # regiones
        piel[B == 1] = m("cesped")
        bos = B == 3
        piel[bos] = np.where(mancha[bos] < 0.42, m("hojarasca"), m("cesped_oscuro"))
        des = B == 4
        piel[des] = np.where(mancha[des] < 0.5, m("arena_desierto"), m("arena_duna"))
        sub[des] = m("arena_desierto")
        hondo[des] = m("roca_roja")
        sel = B == 5
        piel[sel] = np.where(mancha[sel] < 0.45, m("tierra_selva"), m("musgo"))
        sub[sel] = m("tierra_selva")
        mon = B == 2
        piel[mon] = np.where(mancha[mon] < 0.5, m("cesped_seco"), m("cesped"))
        # la roca asoma en lo empinado y en lo alto; nieve en las cumbres
        roca = (pend > 0.85) | ((H > 20.0) & (mancha > 0.45)) | (H > 27.0)
        piel[roca & ~des] = m("roca_monte")
        sub[roca & ~des] = m("roca_monte")
        piel[(pend > 1.6) & ~des] = m("roca_oscura")
        nieve = (H > 34.0 + (mancha - 0.5) * 6.0) & (pend < 1.5)
        piel[nieve] = m("nieve")
        # mesetas: roca roja con estratos (el hondo se elige por altura al rellenar)
        piel[self.bandas & (pend > 0.6)] = m("roca_roja")
        hondo[self.bandas] = m("roca_roja")
        sub[self.bandas] = m("roca_roja_clara")
        # costa: playa y fondo del mar
        playa = (H < D.MAR_Y + 1.6) & (self.dcosta < 26.0)
        piel[playa] = m("arena_playa")
        sub[playa] = m("arena_playa")
        agua = H < D.MAR_Y + 0.05
        piel[agua] = m("arena_mojada")
        sub[agua] = m("arena_mojada")
        orilla = (H >= D.MAR_Y + 0.05) & (H < D.MAR_Y + 0.5)
        piel[orilla & ~playa] = m("tierra")
        # zonas: parcelas con material propio, calles, plazas
        for x0, z0, x1, z1, _y, _f, mat in self.aplanados:
            if mat:
                sx, sz = self._ventana(x0, z0, x1, z1)
                piel[sx, sz] = m(mat)
        for tipo, dd, mat in self.pintados:
            if tipo == "rect":
                sx, sz = self._ventana(*dd)
                piel[sx, sz] = m(mat)
            else:
                cx, cz, r = dd
                sx, sz = self._ventana(cx - r, cz - r, cx + r, cz + r)
                dsk = np.hypot(self.X[sx, sz] - cx, self.Z[sx, sz] - cz) <= r
                piel[sx, sz] = np.where(dsk, m(mat), piel[sx, sz])
        # carreteras encima de todo
        c = self._mat_carr != 255
        piel[c] = self._mat_carr[c]
        sub[c] = m("grava")
        p = self._pint_carr != 255
        piel[p] = self._pint_carr[p]
        self.piel, self.sub, self.hondo = piel, sub, hondo
        # cota (en voxels) desde la que se rellena cada columna: ver `volumen`
        nv = np.round(H / VS).astype(np.int32)
        C = N // 32
        mn = nv.reshape(C, 32, C, 32).min(axis=(1, 3))
        mn = ndimage.minimum_filter(mn, size=3, mode="nearest")
        corte = np.maximum(0, (mn // 32 - 1) * 32)
        for x0, z0, x1, z1 in self.macizos:
            a0, b0 = max(0, int(x0 / D.CHUNK_M) - 1), max(0, int(z0 / D.CHUNK_M) - 1)
            a1, b1 = min(C, int(x1 / D.CHUNK_M) + 2), min(C, int(z1 / D.CHUNK_M) + 2)
            corte[a0:a1, b0:b1] = 0
        self.corte = np.repeat(np.repeat(corte, 32, 0), 32, 1).astype(np.int16)
        del self._w_carr, self._mat_carr, self._pint_carr

    # ------------------------------------------------------------------ para el rasterizador
    def volumen(self, id_de, ax0, ax1, az0, az1, alto):
        """Volumen uint8 (x, y, z) de la ventana con el terreno relleno. Fuera del mundo, vacio."""
        vol = np.zeros((ax1 - ax0, alto, az1 - az0), np.uint8)
        i0, i1 = max(ax0, 0), min(ax1, N)
        k0, k1 = max(az0, 0), min(az1, N)
        lut = np.array([id_de[n] for n in self.mats] + [0] * (256 - len(self.mats)), np.uint8)
        n = np.round(self.H[i0:i1, k0:k1] / VS).astype(np.int16)
        piel = lut[self.piel[i0:i1, k0:k1]]
        sub = lut[self.sub[i0:i1, k0:k1]]
        hondo = lut[self.hondo[i0:i1, k0:k1]]
        band = self.bandas[i0:i1, k0:k1]
        roja, clara = id_de["roca_roja"], id_de["roca_roja_clara"]
        base = id_de["roca_base"]
        nb = int(round(D.BASE_Y / VS))
        dst = vol[i0 - ax0:i1 - ax0, :, k0 - az0:k1 - az0]
        # EL MONTE POR DENTRO, HUECO POR CHUNKS ENTEROS. Lo que queda mas de un chunk por debajo de la
        # superficie mas baja de su chunk y de los ocho de alrededor no se rellena: nadie lo va a ver y cada
        # chunk macizo cuesta 32 KB y su malla de colision. Como el terreno entero es ancla, la costra que
        # queda no se cae. El techo de la cueva es plano y alineado al chunk: unos pocos quads.
        vacio = self.corte[i0:i1, k0:k1]
        lejos = self.dcosta[i0:i1, k0:k1] < -D.MAR_LEJOS
        for y in range(min(alto, int(n.max()) + 1)):
            d = n - 1 - y                                     # profundidad bajo la superficie (0 = arriba)
            capa = np.where(d < PIEL, piel, np.where(d < PIEL + SUB, sub, hondo))
            if band.any():
                estrato = clara if (y // 8) % 3 == 1 else roja
                capa = np.where(band & (d >= PIEL), estrato, capa)
            if y < nb:
                capa = np.full_like(capa, base)
            dst[:, y, :] = np.where((d >= 0) & ((y < nb) | (y >= vacio)) & ~lejos, capa, 0)
        return vol
