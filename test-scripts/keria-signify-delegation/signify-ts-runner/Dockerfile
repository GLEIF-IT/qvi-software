FROM node:24-alpine

WORKDIR /runner
COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src

ENTRYPOINT ["node", "/runner/src/delegation.mjs"]
