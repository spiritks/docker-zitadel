FROM tozd/postfix:ubuntu-noble

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sasl2-bin \
    libsasl2-modules \
  && rm -rf /var/lib/apt/lists/*

COPY run.config /etc/service/postfix/run.config
COPY run.initialization /etc/service/postfix/run.initialization
RUN chmod 755 /etc/service/postfix/run.config /etc/service/postfix/run.initialization
