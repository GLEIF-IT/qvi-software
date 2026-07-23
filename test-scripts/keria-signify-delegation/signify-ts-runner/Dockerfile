FROM node:24-alpine

WORKDIR /runner
COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src

CMD ["npm", "run", "setup"]
