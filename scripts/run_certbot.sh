#!/bin/sh

LOGFILE="/var/log/letsencrypt/certrenewal.log"

logger_error() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] ${1}" >> ${LOGFILE}
  fi
  >&2 echo "[error] ${1}"
}

logger_info() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] ${1}" >> ${LOGFILE}
  else
    echo "[info] ${1}"
  fi
}

issueCertificate() {
  certbot certonly --agree-tos --renew-by-default --non-interactive --email $EMAIL $args -d $1 &>/dev/null
  return $?
}

processCertificates() {
  # Gets the certificate for the domain(s) CERT_DOMAIN (a comma separated list)
  # The certificate will be named after the first domain in the list
  # To work, the following variables must be set:
  # - CERT_DOMAIN : comma separated list of domains
  # - EMAIL
  # - CONCAT
  # - args

  local d=${CERT_DOMAIN} # shorthand

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
            domains="${domains} -d ${altname}"
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
        fi

      else
        logger_info "Certificate for $d does not require renewal"
      fi
    fi
  else
    logger_info "Getting certificate for $CERT_DOMAIN"
    issueCertificate "${CERT_DOMAIN}"

    if [ $? -ne 0 ]; then
      logger_error "Failed to request certificate! check /var/log/letsencrypt/letsencrypt.log!"
      exitcode=1
    else
      if $CONCAT; then
        # concat the full chain with the private key (e.g. for haproxy)
        cat /etc/letsencrypt/live/$d/fullchain.pem /etc/letsencrypt/live/$d/privkey.pem > /certs/$d.pem
      else
        # keep full chain and private key in separate files (e.g. for nginx and apache)
        cp /etc/letsencrypt/live/$d/cert.pem /certs/$d.pem
        cp /etc/letsencrypt/live/$d/privkey.pem /certs/$d.key.pem
        cp /etc/letsencrypt/live/$d/chain.pem /certs/$d.chain.pem
        cp /etc/letsencrypt/live/$d/fullchain.pem /certs/$d.fullchain.pem
      fi
      logger_info "Certificate delivered for $CERT_DOMAIN"
    fi
  fi
}

args=""
if [ $WEBROOT ]; then
  args=" --webroot -w $WEBROOT"
else
  args=" --standalone --preferred-challenges tls-sni"
fi

if $DEBUG; then
  args=$args" --debug"
fi

if $STAGING; then
  args=$args" --staging"
fi

NOW=$(date +"%D %T")
logger_info "$NOW: Checking certificates for domains $DOMAINS"

for d in $DOMAINS; do
  CERT_DOMAIN=$d
  processCertificates
done
