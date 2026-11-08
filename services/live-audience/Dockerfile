FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY bridge.mjs normalize.mjs ./
USER node
CMD ["node", "bridge.mjs"]
