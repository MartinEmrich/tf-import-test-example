#!/bin/bash

if [ "$AWS_PROFILE" = "" ]; then
    echo "AWS_PROFILE is not set."
    exit 1
fi
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1


aws ec2 delete-key-pair --key-name tf-import-test && rm -f tf-import-test.pm
rm -rf tf/.terraform
rm -f tf/.terraform.lock.hcl
