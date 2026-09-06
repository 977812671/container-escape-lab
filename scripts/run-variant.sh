#!/usr/bin/env bash
set -eu
VARIANT="${1:?variant required: privileged|sock|plain}"
case "$VARIANT" in
  privileged) DOCKER_OPTS="--privileged -v /:/host" ;;
  sock)       DOCKER_OPTS="-v /var/run/docker.sock:/var/run/docker.sock" ;;
  plain)      DOCKER_OPTS="" ;;
  *) echo "unknown variant $VARIANT"; exit 1 ;;
esac
docker run --rm $DOCKER_OPTS -v "$PWD":/lab -e VARIANT="$VARIANT" alpine:3.19 sh /lab/scripts/in-container.sh "$VARIANT"
echo "=== variant $VARIANT done ==="
ls -la reports/
