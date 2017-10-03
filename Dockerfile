FROM certbot/certbot

RUN mkdir /certs

ADD crontab /etc/crontabs
RUN crontab /etc/crontabs/crontab

COPY ./scripts/ /

ENTRYPOINT ["/bin/sh", "-c"]

CMD ["/run_cron.sh"]
