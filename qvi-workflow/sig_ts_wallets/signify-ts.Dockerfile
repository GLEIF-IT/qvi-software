FROM gleif/tsx:1.0.0 AS builder

WORKDIR /vlei-workflow

COPY package.json ./
COPY package-lock.json ./
COPY tsconfig.json ./
RUN npm ci

# Building the runtime image should be much faster since it will reuse prior dependencies
FROM builder AS runtime
WORKDIR /vlei-workflow

RUN apk add --no-cache bash

COPY src ./src

CMD ["tsx"]
