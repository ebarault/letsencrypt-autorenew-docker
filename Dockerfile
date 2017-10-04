FROM certbot/certbot:v0.18.2
MAINTAINER Eric Barault (@ebarault)

VOLUME /certs
VOLUME /etc/letsencrypt
EXPOSE 443

RUN apk update && \
	apk add openssl

ADD crontab /etc/crontabs
RUN crontab /etc/crontabs/crontab

COPY ./scripts/ /scripts
RUN chmod -R +x /scripts/

ENTRYPOINT ["/scripts/entrypoint.sh"]
