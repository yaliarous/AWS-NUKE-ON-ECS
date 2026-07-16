#!/bin/sh
set -e

: "${TARGET_ACCOUNT_IDS:?TARGET_ACCOUNT_IDS must be set}"
: "${AWS_REGION:?AWS_REGION must be set}"

# Convert comma-separated string to list and process each one
OLD_IFS="$IFS"
IFS=","
set -- $TARGET_ACCOUNT_IDS
IFS="$OLD_IFS"
for ACCOUNT_ID; do
    echo "Processing account: $ACCOUNT_ID"

    # Create account-specific nuke config
    sed -e "s/{{ACCOUNT_ID}}/${ACCOUNT_ID}/g" \
        -e "s/{{AWS_REGION}}/${AWS_REGION}/g" /app/nuke-config.yml.template > "/app/nuke-config-${ACCOUNT_ID}.yml"

    # Run aws-nuke for this account
    aws-nuke nuke -c "/app/nuke-config-${ACCOUNT_ID}.yml"  --assume-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aws-nuke-role" --no-prompt --no-dry-run --no-alias-check 

    # Clean up the temporary config
    #rm "/app/nuke-config-${ACCOUNT_ID}.yml"
done