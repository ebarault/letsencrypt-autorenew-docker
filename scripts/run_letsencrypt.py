#!/usr/bin/env python
import commands
from datetime import datetime
import os
from shutil import copy


RENEWAL_DAYS = 28
cert_dir = '/etc/letsencrypt/live'
cert_copy_dir = '/certs'


def ensure_dh_params():
    dh_params_path = os.path.join(cert_copy_dir, 'dhparams.pem')
    if not os.path.exists(dh_params_path):
        print('Generating DH parameters, 2048 bit long safe prime. This will take a while.')
        commands.getoutput('openssl dhparam -out {} 2048'.format(dh_params_path))


def renew_domains():
    regeneratedAnything = False
    print("=== {}: Renewing Domains ===".format(datetime.now().strftime("%d.%m.%y %H:%M")))
    for domain in os.environ['DOMAINS'].split(' '):
        cert_path = os.path.join(cert_dir, domain, 'fullchain.pem')
        cert_copy_path = os.path.join(cert_copy_dir, '{}.pem'.format(domain))
        key_path = os.path.join(cert_dir, domain, 'privkey.pem')
        key_copy_path = os.path.join(cert_copy_dir, '{}.key'.format(domain))

        print("Checking {}...".format(domain))

        generate = False

        if not os.path.exists(cert_path):
            generate = True
        else:
            expiry_date = commands.getoutput('openssl x509 -noout -in {} -dates'.format(cert_path))
            expiry_date = expiry_date.split('\n')[1].replace('notAfter=', '')
            expiry_date = datetime.strptime(expiry_date, '%b %d %H:%M:%S %Y %Z')
            if (expiry_date - datetime.now()).days <= RENEWAL_DAYS:
                generate = True

        if generate:
            print("Running letsencrypt for {}".format(domain))
            regeneratedAnything = True

            exit_code, result = commands.getstatusoutput('certbot --standalone  --preferred-challenges\
              http-01 --agree-tos --renew-by-default\
              --server https://acme-v01.api.letsencrypt.org/directory\
              --email $EMAIL -d {} certonly'.format(domain))
            if exit_code > 0:
                print(result)
                exit(1)
            else:
                if os.environ['MERGE_KEY_WITH_CERTIFICATE'] == 'true':
                    outfile = open(cert_copy_path, 'w')
                    outfile.write(open(cert_path).read())
                    outfile.write(open(key_path).read())
                else:
                    copy(key_path, key_copy_path)
                    copy(cert_path, cert_copy_path)

    if not regeneratedAnything:
        print("No need to regenerate Anything.\n")

if __name__ == '__main__':
    if os.environ['DH_PARAMETERS'] == 'true':
        ensure_dh_params()
    renew_domains()
