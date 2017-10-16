#!/bin/sh
echo "Waiting for $HEALTH_CHECK_URL to be online"

until [ $(curl -s -L --head --fail -o /dev/null -w '%{http_code}\n' --connect-timeout 3 --max-time 5 $HEALTH_CHECK_URL) -eq 200 ]; do
  printf '.'
  sleep 5
  # -s = Silent cURL's output
  # -L = Follow redirects
  # -w = Custom output format
  # -o = Redirects the HTML output to /dev/null
done

# one-time execution at container start once host's health check is ok
/scripts/run_certbot.sh

# scheduling periodic executions
exec crond -f
