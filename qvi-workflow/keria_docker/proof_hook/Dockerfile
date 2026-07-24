FROM gleif/sally:1.0.2

WORKDIR /app

COPY __init__.py recorder.py evidence.py workflow_contracts.py ./

RUN mkdir /proof \
    && chown 65532:65532 /proof

VOLUME ["/proof"]

USER 65532:65532

ENTRYPOINT ["python3", "/app/recorder.py"]
