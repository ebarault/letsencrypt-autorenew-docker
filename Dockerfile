FROM certbot/certbot

VOLUME /certs
VOLUME /etc/letsencrypt
EXPOSE 80

# RUN mkdir /certs

ADD crontab /etc/crontabs
RUN crontab /etc/crontabs/crontab

COPY ./scripts/ /
RUN chmod +x /run_cron.sh

ENTRYPOINT ["/bin/sh", "-c"]

CMD ["/run_cron.sh"]
