#!/bin/sh

# boostrapped from https://github.com/janeczku/haproxy-acme-validation-plugin/blob/master/cert-renewal-haproxy.sh

logger_error() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] ${1}" >> ${LOGFILE}
  fi
  # make sure the job redirects directly to stdout/stderr instead of a log file
  # this works well in docker combined with a docker logging driver
  >&2 echo "[error] ${1}" > /proc/1/fd/1 2>/proc/1/fd/2
}

logger_info() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] ${1}" >> ${LOGFILE}
  else
    # make sure the job redirects directly to stdout/stderr instead of a log file
    # this works well in docker combined with a docker logging driver
    echo "[info] ${1}" > /proc/1/fd/1 2>/proc/1/fd/2
  fi
}

issueCertificate() {
  certbot_response=`certbot certonly --agree-tos --renew-by-default --non-interactive --max-log-backups 100 --email $EMAIL $CERTBOT_ARGS -d $1 2>&1`
  certbot_return_code=$?
  logger_info "${certbot_response}"
  return ${certbot_return_code}
}

copyCertificate() {
  local d=${CERT_DOMAIN%%,*} # in case of multi-host domains, use first name only

  # certs are copied to /certs directory
  if [ "$CONCAT" = true ]; then
   # concat the full chain with the private key (e.g. for haproxy)
   cat /etc/letsencrypt/live/$d/fullchain.pem /etc/letsencrypt/live/$d/privkey.pem > /certs/$d.pem
   logger_info "Certificates for $d concatenated and copied to /certs dir"
  else
   # keep full chain and private key in separate files (e.g. for nginx and apache)
   cp /etc/letsencrypt/live/$d/cert.pem /certs/$d.pem
   cp /etc/letsencrypt/live/$d/privkey.pem /certs/$d.key.pem
   cp /etc/letsencrypt/live/$d/chain.pem /certs/$d.chain.pem
   cp /etc/letsencrypt/live/$d/fullchain.pem /certs/$d.fullchain.pem
   logger_info "Certificates for $d and copied to /certs dir"
  fi
}

processCertificates() {
  # Get the certificate for the domain(s) CERT_DOMAIN (a comma separated list)
  # The certificate will be named after the first domain in the list
  # To work, the following variables must be set:
  # - CERT_DOMAIN : comma separated list of domains
  # - EMAIL
  # - CONCAT
  # - CERTBOT_ARGS

  local d=${CERT_DOMAIN%%,*} # in case of multi-host domains, use first name only

  if [ -d /etc/letsencrypt/live/$d ]; then
    cert_path=$(find /etc/letsencrypt/live/$d -name cert.pem -print0)
    if [ $cert_path ]; then
      # check for certificates expiring in less that 28 days
      if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert_path}"; then
        subject="$(openssl x509 -noout -subject -in "${cert_path}" | grep -o -E 'CN=[^ ,]+' | tr -d 'CN=')"
        subjectaltnames="$(openssl x509 -noout -text -in "${cert_path}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
        domains="${subject}"

        # look for certificate additional domain names and append them as '-d <name>' (-d for certbot's --domains option)
        for altname in ${subjectaltnames}; do
          if [ "${altname}" != "${subject}" ]; then
            if [ "${domains}" != "" ]; then
              domains="${domains} -d ${altname}"
            else
              domains="${altname}"
            fi
          fi
        done

        # renewing certificate
        logger_info "Renewing certificate for $domains"
        issueCertificate "${domains}"

        if [ $? -ne 0 ]; then
          logger_error "Failed to renew certificate! check /var/log/letsencrypt/letsencrypt.log!"
          exitcode=1
        else
          logger_info "Renewed certificate for ${subject}"
          copyCertificate
        fi

      else
        logger_info "Certificate for $d does not require renewal"
      fi
    fi
  else
    # initial certificate request
    logger_info "Getting certificate for $CERT_DOMAIN"
    issueCertificate "${CERT_DOMAIN}"

    if [ $? -ne 0 ]; then
      logger_error "Failed to request certificate! check /var/log/letsencrypt/letsencrypt.log!"
      exitcode=1
    else
      logger_info "Certificate delivered for $CERT_DOMAIN"
      copyCertificate
    fi
  fi
}

## ================================== MAIN ================================== ##

# bootstrap a list of optional arguments for certbot
CERTBOT_ARGS=""

##
# trigger certbot's webroot / standalone plugin
#
# `webroot` plugin is recommended when you already have a web server running
# $WEBROOT should be set to the existing web server's root for certbot to use this mode
# see https://certbot.eff.org/docs/using.html#webroot
#
# `standlone` plugin runs a built-in “standalone” web server to obtain the certificate
# The current implementation supports the http-01, dns-01 and tls-alpn-01 challenges and
# defaults to http-01 since tls-sni-01 has been deprecated
# This mode is triggered when $WEBROOT is not set
# see https://certbot.eff.org/docs/using.html#standalone
#
if [ $WEBROOT ]; then
  CERTBOT_ARGS=" --webroot -w $WEBROOT"
else
  CERTBOT_ARGS=" --${PLUGIN:-standalone} --preferred-challenges ${PREFERRED_CHALLENGES:-http-01} ${CUSTOM_ARGS}"
fi

# activate debug mode
if [ "$DEBUG" = true ]; then
  CERTBOT_ARGS=$CERTBOT_ARGS" --debug"
fi

# activate staging mode where test certificates (invalid) are requested against
# letsencrypt's staging server https://acme-staging.api.letsencrypt.org/directory.
# This is useful for testing purposes without being rate limited by letsencrypt
if [ "$STAGING" = true ]; then
  CERTBOT_ARGS=$CERTBOT_ARGS" --staging"
fi

NOW=$(date +"%D %T")
logger_info "$NOW: Checking certificates for domains $DOMAINS"

##
# extract certificate domains and run main routine on each
# $DOMAINS is expected to be space separated list of domains such as in "foo bar baz"
# each domains subset can be composed of several domains in case of multi-host domains,
# they are expected to be comma separated, such as in "foo bar,bat baz"
#
for d in $DOMAINS; do
  CERT_DOMAIN=$d
  processCertificates
done
