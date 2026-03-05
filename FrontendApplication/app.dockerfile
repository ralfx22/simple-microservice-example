FROM nginx:1.10

ADD vhost.conf.tmpl /etc/nginx/templates/vhost.conf.tmpl

COPY ./dist /var/www
COPY ./config/config.js.tmpl /etc/nginx/templates/config.js.tmpl
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
