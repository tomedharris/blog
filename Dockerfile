FROM jguyomard/hugo-builder

COPY . /src

RUN git submodule update --init --recursive

CMD hugo -D