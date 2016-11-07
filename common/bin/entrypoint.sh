#!/bin/sh

set -e

grep nameserver /etc/resolv.conf \
  | awk '{print  "resolver " $2 ";"}' \
  > /usr/local/openresty/nginx/conf/resolvers.conf

/usr/local/openresty/bin/openresty -g 'daemon off;' "$@"
