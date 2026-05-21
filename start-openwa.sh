#!/bin/sh
# Start nginx (dashboard) and OpenWA API concurrently
set -e

nginx -g 'daemon off;' &
node dist/main
