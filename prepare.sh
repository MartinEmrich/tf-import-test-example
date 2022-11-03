#!/bin/bash

set +x

if [ "$AWS_PROFILE" = "" ]; then
    echo "AWS_PROFILE is not set."
    exit 1
fi
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1

if ! ( which jq ); then
    echo "\"jq\" is missing, please install it."
    exit 1
fi

if ! [ -f tf-import-test.pem ]; then
    echo "Creating AWS EC2 Keypair"
    aws ec2 create-key-pair --key-name tf-import-test --key-type ed25519 --key-format pem | tee /dev/stderr | jq -r .KeyMaterial | tee tf-import-test.pem
else
    echo "AWS EC2 keypair already created."
fi

TF_STATE_BUCKET=tf-import-test-terraform
if ! (aws s3api head-bucket --bucket $TF_STATE_BUCKET); then
  aws s3 mb s3://$TF_STATE_BUCKET
  aws s3api put-public-access-block --bucket $TF_STATE_BUCKET \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi


DNSDOMAIN=tf-import-test.example.zz
ROUTE53HOSTEDZONEID=$(aws route53 list-hosted-zones | jq ".HostedZones[] | select(.Name == \"${DNSDOMAIN}.\") | .Id" -r | sed 's/\/hostedzone\///')
if [ "$ROUTE53HOSTEDZONEID" = "" ]; then
    echo "Creating Route53 hosted zone"
    aws route53 create-hosted-zone --name $DNSDOMAIN --caller-reference tf-import-test-example | tee create-hosted-zone-result.json
fi
aws route53 list-hosted-zones | jq ".HostedZones[] | select(.Name == \"${DNSDOMAIN}.\") | .Id" -r | sed 's/\/hostedzone\///' | tee zone-id.txt

./terraform init