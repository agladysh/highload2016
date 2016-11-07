FROM openresty/openresty:latest

COPY bin/entrypoint.sh /usr/local/bin/openresty-entrypoint.sh

COPY nginx/conf /usr/local/openresty/nginx/conf
COPY nginx/lualib /usr/loca/openresty/nginx/lualib

ENTRYPOINT /usr/local/bin/openresty-entrypoint.sh
