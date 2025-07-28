FROM apache/nifi:1.28.1

USER root

# 1) Instalar wget (e any other tools necessários)
RUN apt-get update \
 && apt-get install -y wget \
 && rm -rf /var/lib/apt/lists/*

# 2) Ajustar permissões da conf para o usuário nifi (UID 1000)
RUN chown -R 1000:1000 /opt/nifi/nifi-current/conf \
 && chmod -R 700 /opt/nifi/nifi-current/conf

USER nifi
