FROM node:22-alpine

WORKDIR /app

# 1. Dépendances d'abord : cette couche ne se reconstruit que si package*.json change
COPY package*.json ./
RUN npm ci --omit=dev

# 2. Code ensuite : change souvent, donc en bas
COPY server.js db.js ./

EXPOSE 3000

CMD ["node", "server.js"]
