#!/bin/bash

SSL_URL=${GETNAME_SSL_URL}

wget $SSL_URL/fullchain.pem -O /etc/ssl/fullchain.pem --no-check-certificate
wget $SSL_URL/privkey.pem -O /etc/ssl/privkey.pem --no-check-certificate
wget $SSL_URL/ssl-dhparams.pem -O /etc/ssl/ssl-dhparams.pem --no-check-certificate
