FROM python:3.12-slim

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsodium23 \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install \
    "keri==1.2.13" \
    "signifypy==0.4.2"

WORKDIR /runner
COPY src/delegation.py /runner/delegation.py

ENTRYPOINT ["python", "/runner/delegation.py"]
