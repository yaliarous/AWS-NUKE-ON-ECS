#!/bin/sh
set -e

: "${TARGET_ACCOUNT_ID:?TARGET_ACCOUNT_ID must be set}"

sed "s/{{ACCOUNT_ID}}/${TARGET_ACCOUNT_ID}/g" /app/nuke-config.yml.template > /app/nuke-config.yml

exec aws-nuke "$@"