# Servidor de cuentas de Breach

Servicio HTTP para Cloud Run: registro, inicio de sesión y progreso de cuenta (experiencia, monedas,
armas compradas). Los datos van en **JSON dentro de un bucket de Cloud Storage**.

```
godot/scripts/cuenta.gd  ──HTTPS──>  Cloud Run (este servidor)  ──REST──>  bucket GCS
                                                                            cuentas/<usuario>.json
```

---

## Las decisiones, y por qué

### Un JSON POR CUENTA, no un JSON con todas

Pediste "un JSON". Con un único fichero para todos los jugadores hay dos problemas que aparecen justo
cuando el juego empieza a funcionar:

1. **Se pisan.** Cloud Run levanta **varias instancias a la vez**. Si dos partidas terminan al mismo
   tiempo, las dos leen el JSON, las dos suman su premio y las dos lo escriben: gana la última y el
   otro premio **se pierde**.
2. **Cada escritura cuesta el fichero entero.** Con 500 cuentas, guardar 40 monedas reescribe medio
   mega. Eso se come la cuota gratis de operaciones y de ancho de banda.

Con un fichero por cuenta (`cuentas/pepe.json`) los dos desaparecen: dos jugadores distintos nunca
tocan el mismo objeto, y cada escritura son 300 bytes. Sigue siendo JSON, sigue sin haber base de
datos, y se puede abrir con el bloc de notas.

**El mismo jugador desde dos sitios a la vez** sí puede chocar, y eso se resuelve con
`ifGenerationMatch` (control de concurrencia optimista): se lee el objeto con su *generación*, se
modifica y se escribe exigiendo que la generación no haya cambiado. Si cambió, se reintenta. Nunca se
pierde un premio.

### El nombre de usuario ES el nombre del fichero

Así la unicidad sale gratis y **sin condición de carrera**: registrar es crear el objeto con
`ifGenerationMatch=0`, que falla si ya existe. No hace falta un índice aparte ni comprobar-y-luego-crear
(que es justo donde se cuelan los duplicados).

### Cero dependencias de npm

El servidor usa solo módulos de Node (`http`, `crypto`). Habla con Cloud Storage por su **API REST**,
pidiendo el token al **servidor de metadatos** de Cloud Run (la cuenta de servicio ya está ahí: no hay
claves que guardar ni que rotar).

Eso no es purismo: `npm install` mete decenas de megas en la imagen, y **el arranque en frío lo pagas
en CPU facturable**. Sin dependencias la imagen es de unos 100 MB (solo la base de Node) y arranca en
milisegundos, que es exactamente lo que mantiene el servicio dentro de la cuota gratis.

### El premio lo calcula el SERVIDOR

El cliente manda **lo que pasó** ("modo oleadas, gané, oleada 10, 47 bajas"), nunca lo que ha ganado.
Si el cliente mandara "he ganado 600 EXP", cualquiera con un proxy manda 600.000. Las fórmulas viven
en `PREMIOS` y el cliente no las conoce.

Además hay tres frenos: tope de premio por partida, **duración mínima** de partida (una partida de
3 segundos no paga) y tope de partidas por hora.

---

## La cuota gratis, y cómo no pasarse

| Recurso | Gratis al mes | Lo que gasta esto |
|---|---|---|
| Cloud Run peticiones | 2.000.000 | 4-5 por partida |
| Cloud Run CPU/memoria | 180.000 vCPU-s · 360.000 GiB-s | escala a cero; 512 MiB |
| GCS almacenamiento | 5 GB | ~300 bytes por cuenta |
| GCS escrituras (clase A) | 5.000 | **1 por partida terminada** |
| GCS lecturas (clase B) | 50.000 | 1 por inicio de sesión (con caché) |

Las escrituras son el recurso escaso: 5.000 al mes. Por eso **solo se escribe al terminar una
partida**, nunca en el lobby ni al mirar el perfil.

Tres cosas que lo sostienen:

* **`--min-instances=0`**: sin tráfico no se paga nada. El precio es el arranque en frío, que aquí es
  corto justo por no tener dependencias.
* **`--concurrency=80`**: una sola instancia atiende 80 peticiones a la vez. Esto es E/S casi pura, así
  que no hace falta más instancia.
* **Caché en memoria** (`CACHE_MS`): leer el perfil dos veces seguidas no vuelve a bajar el objeto.
  El token se valida con criptografía, **sin tocar el bucket**.

---

## Desplegar

```bash
# 1) el bucket (una sola vez). us-central1 entra en la capa gratis de GCS.
gcloud storage buckets create gs://TU-BUCKET-breach --location=us-central1 --uniform-bucket-level-access

# 2) un secreto para firmar los tokens. Guárdalo: si cambia, todos tienen que volver a entrar.
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# 3) desplegar
cd servidor
gcloud run deploy breach-cuentas \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=2 \
  --concurrency=80 \
  --memory=512Mi \
  --cpu=1 \
  --set-env-vars=BREACH_BUCKET=TU-BUCKET-breach,BREACH_SECRET=EL_SECRETO_DE_ARRIBA
```

`--max-instances=2` es un **tope de gasto**, no de rendimiento: con 80 peticiones simultáneas por
instancia, dos instancias sirven a cientos de jugadores. Sin ese tope, un pico (o un bucle en el
cliente) puede escalar a 100 instancias y sacarte de la capa gratis en una tarde.

La cuenta de servicio del servicio necesita escribir en el bucket:

```bash
PROY=$(gcloud config get-value project)
NUM=$(gcloud projects describe $PROY --format='value(projectNumber)')
gcloud storage buckets add-iam-policy-binding gs://TU-BUCKET-breach \
  --member=serviceAccount:$NUM-compute@developer.gserviceaccount.com \
  --role=roles/storage.objectAdmin
```

## Probar en local, sin nube

```bash
cd servidor
BREACH_SECRET=pruebas BREACH_LOCAL=./datos node index.js
```

Con `BREACH_LOCAL` los JSON se guardan en esa carpeta en vez de en el bucket. Es el mismo código
salvo la capa de almacenamiento, así que sirve para probar el juego entero sin gastar cuota.

```bash
node prueba.js            # 15 comprobaciones contra el servidor local
```

## La API

| Ruta | Qué hace |
|---|---|
| `POST /registro` | `{usuario, clave}` → crea la cuenta y devuelve token + perfil |
| `POST /entrar` | `{usuario, clave}` → token + perfil |
| `GET /perfil` | (con token) el perfil |
| `POST /partida` | (con token) `{modo, gano, segundos, oleada, bajas, puntos}` → premio y perfil nuevo |
| `POST /compra` | (con token) `{arma}` → descuenta monedas y apunta el arma |
| `GET /salud` | para comprobar que está vivo |
| `POST /regalo/reclamar` | (con token) `{ids}` → suma los regalos del panel (vacío = todos) |
| `/admin/*` | el panel de administración (`admin.js`, app `admin/`): ver [admin/README.md](../admin/README.md) |

El token va en `Authorization: Bearer <token>` y dura 30 días.
