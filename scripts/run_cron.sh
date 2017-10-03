#!/bin/sh

echo "export DOMAINS=\"$DOMAINS\"" > /var/tmp/env.sh
echo "export EMAIL=\"$EMAIL\"" >> /var/tmp/env.sh
echo "export DH_PARAMETERS=\"$DH_PARAMETERS\"" >> /var/tmp/env.sh
echo "export MERGE_KEY_WITH_CERTIFICATE=\"$MERGE_KEY_WITH_CERTIFICATE\"" >> /var/tmp/env.sh
echo "export PATH=\"$PATH\"" >> /var/tmp/env.sh

crond -f
