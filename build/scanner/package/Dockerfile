ARG BCI_VERSION=15.7
ARG SCANNER_IMAGE=neuvector/scanner:latest
ARG REPO=neuvector
FROM registry.suse.com/bci/bci-base:${BCI_VERSION} AS base
RUN zypper in -y wget
RUN mkdir -p stage/etc/neuvector/certs/internal
RUN wget https://raw.githubusercontent.com/neuvector/manifests/989d9058bfb8e1d2126b17a30c3d57371c4d5cef/build/share/etc/neuvector/certs/internal/ca.cert -O stage/etc/neuvector/certs/internal/ca.cert
RUN wget https://raw.githubusercontent.com/neuvector/manifests/989d9058bfb8e1d2126b17a30c3d57371c4d5cef/build/share/etc/neuvector/certs/internal/cert.key -O stage/etc/neuvector/certs/internal/cert.key
RUN wget https://raw.githubusercontent.com/neuvector/manifests/989d9058bfb8e1d2126b17a30c3d57371c4d5cef/build/share/etc/neuvector/certs/internal/cert.pem -O stage/etc/neuvector/certs/internal/cert.pem
RUN chmod 660 stage/etc/neuvector/certs/internal/*

FROM ${SCANNER_IMAGE}
COPY --from=base stage/ /
