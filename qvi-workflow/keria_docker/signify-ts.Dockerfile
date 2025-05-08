FROM gleif/tsx:1.0.0

WORKDIR /vlei-workflow

COPY package.json ./
COPY package-lock.json ./
COPY tsconfig.json ./
COPY signify_qvi ./signify_qvi

RUN npm install

CMD ["tsx"]
