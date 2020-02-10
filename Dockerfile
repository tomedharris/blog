FROM jguyomard/hugo-builder

COPY . /src

RUN git submodule update --init --recursive

CMD hugo --config config.live.toml