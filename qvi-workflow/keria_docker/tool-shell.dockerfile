FROM weboftrust/keri:1.1.32

# install deno
RUN apk add --no-cache \
    bash \
    curl \
    nodejs npm

SHELL ["/bin/bash", "-c"]

# install tsx \
RUN npm install -g tsx@latest

