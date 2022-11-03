#!/bin/bash

if ! [ -f zone-id.txt ]; then
    echo "zone-id.txt missing, run prepare.sh first."
    exit 1
fi

ROUTE53HOSTEDZONEID=$(cat zone-id.txt)

./terraform import aws_route53_zone.platformdomain $ROUTE53HOSTEDZONEID