LOGFILE="/var/log/certrenewal.log"

function logger_error {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] ${1}" >> ${LOGFILE}
  fi
  >&2 echo "[error] ${1}"
}

function logger_info {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] ${1}" >> ${LOGFILE}
  else
    echo "[info] ${1}"
  fi
}

function issueCertificate {
	certbot certonly --agree-tos --renew-by-default --non-interactive --email $EMAIL $args -d $1 &>/dev/null
  return $?
}

function processCertificates() {
  # Gets the certificate for the domain(s) CERT_DOMAIN (a comma separated list)
  # The certificate will be named after the first domain in the list
  # To work, the following variables must be set:
  # - CERT_DOMAIN : comma separated list of domains
  # - EMAIL
  # - CONCAT
  # - args

	local d=${CERT_DOMAIN} # shorthand

	cert_path=$(find /etc/letsencrypt/live/$d -name cert.pem -print0)
	if $cert_path; then
		if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert_path}"; then
    	subject="$(openssl x509 -noout -subject -in "${cert_path}" | grep -o -E 'CN=[^ ,]+' | tr -d 'CN=')"
    	subjectaltnames="$(openssl x509 -noout -text -in "${cert_path}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
    	domains="-d ${subject}"

			for name in ${subjectaltnames}; do
	      if [ "${name}" != "${subject}" ]; then
	        domains="${domains} -d ${name}"
	      fi
	    done

			# renewing certificate
			logger_info "Renewing certificate for $domains"
			issueCertificate "${domains}"

	    if [ $? -ne 0 ]; then
	      logger_error "failed to renew certificate! check /var/log/letsencrypt/letsencrypt.log!"
	      exitcode=1
	    else
	      renewed_certs+=("$subject")
	      logger_info "renewed certificate for ${subject}"
	    fi

	  else
	    logger_info "certificate for $d does not require renewal"
	  fi
	else
		logger_info "Getting certificate for $CERT_DOMAIN"
		issueCertificate "${CERT_DOMAIN}"

		if [ $? -ne 0 ]; then
			logger_error "failed to request certificate! check /var/log/letsencrypt/letsencrypt.log!"
			exitcode=1
		else
			if $CONCAT; then
				# concat the full chain with the private key (e.g. for haproxy)
				cat /etc/letsencrypt/live/$d/fullchain.pem /etc/letsencrypt/live/$d/privkey.pem > /certs/$d.pem
			else
				# keep full chain and private key in separate files (e.g. for nginx and apache)
				cp /etc/letsencrypt/live/$d/fullchain.pem /certs/$d.pem
				cp /etc/letsencrypt/live/$d/privkey.pem /certs/$d.key
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
