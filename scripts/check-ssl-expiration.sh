#!/bin/bash
set -euo pipefail

ENV_FILE="/opt/notes/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"

if [[ -z "${NOTES_DOMAIN:-}" ]]; then
    echo "ERROR: NOTES_DOMAIN not set in .env"
    exit 1
fi

CERT_FILE="/etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem"

if [[ ! -f "$CERT_FILE" ]]; then
    echo "ERROR: Certificate not found at $CERT_FILE"
    exit 1
fi

EXPIRY_DATE=$(sudo openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

echo "SSL Certificate Status:"
echo "  Domain:      ${NOTES_DOMAIN}"
echo "  Expires:     ${EXPIRY_DATE}"
echo "  Days left:   ${DAYS_LEFT}"
echo ""

if [[ $DAYS_LEFT -lt 7 ]]; then
    echo "WARNING: Certificate expires in less than 7 days!"
    exit 2
elif [[ $DAYS_LEFT -lt 30 ]]; then
    echo "NOTICE: Certificate expires in less than 30 days"
    exit 0
else
    echo "OK: Certificate is valid"
    exit 0
fi
