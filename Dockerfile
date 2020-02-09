FROM jguyomard/hugo-builder

COPY . /src

CMD hugo -D