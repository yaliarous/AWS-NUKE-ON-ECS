#!/bin/sh
set -e

: "${TARGET_ACCOUNT_ID:?TARGET_ACCOUNT_ID must be set}"
: "${AWS_REGION:?AWS_REGION must be set}"

sed -e "s/{{ACCOUNT_ID}}/${TARGET_ACCOUNT_ID}/g" \
    -e "s/{{AWS_REGION}}/${AWS_REGION}/g" /app/nuke-config.yml.template > /app/nuke-config.yml

exec aws-nuke "$@"