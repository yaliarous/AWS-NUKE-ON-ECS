


# renovate: datasource=docker depName=ghcr.io/ekristen/aws-nuke
FROM ghcr.io/ekristen/aws-nuke:v3.65.0

USER root
COPY ./nuke-config.yml.template /app/nuke-config.yml.template
COPY ./entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

USER aws-nuke
ENTRYPOINT ["/app/entrypoint.sh"]