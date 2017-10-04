#!/bin/sh

# one-time execution at container start
/scripts/run_certbot.sh

# scheduling periodic executions
exec crond -f
