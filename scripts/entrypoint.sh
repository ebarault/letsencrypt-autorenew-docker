#!/bin/sh

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

if [ -n "$HEALTH_CHECK_URL" ] ; then
  logger_info "Waiting for $HEALTH_CHECK_URL to be online"

  # Wait until the server at the provided $HEALTH_CHECK_URL is up before actually running certbot
  until [ $(curl -s -L --head --fail -o /dev/null -w '%{http_code}\n' --connect-timeout 3 --max-time 5 $HEALTH_CHECK_URL) -eq 200 ]; do
    logger_info '.'
    sleep 5
    # -s = Silent cURL's output
    # -L = Follow redirects
    # -w = Custom output format
    # -o = Redirects the HTML output to /dev/null
  done

  logger_info ""
  logger_info "$HEALTH_CHECK_URL is online, running certbot"
else
  logger_info "No HEALTH_CHECK_URL specified; skipping health check"
fi

# one-time execution at container start once host's health check is ok
/scripts/run_certbot.sh

# scheduling periodic executions
exec crond -f
