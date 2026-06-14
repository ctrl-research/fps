FROM node:20-alpine

WORKDIR /app

# Install production deps first for better layer caching. Uses the committed
# lockfile for reproducible builds.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./

ENV PORT=9080
EXPOSE 9080

USER node
CMD ["node", "server.js"]
