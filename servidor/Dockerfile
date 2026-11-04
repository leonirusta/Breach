# Imagen minima: solo la base de Node. Sin `npm install` porque el servidor no tiene dependencias, y
# el arranque en frio de Cloud Run SE PAGA EN CPU: cuanto menos haya que cargar, menos cuota se gasta.
FROM node:22-slim
WORKDIR /app
COPY index.js admin.js reportes.js equipos.js contacto.js puente.js precios.json catalogo.json pase.json progreso.json ./
# no root: si alguna vez hay un fallo de ejecucion remota, que no sea con todos los permisos
USER node
ENV NODE_ENV=production
CMD ["node", "index.js"]
