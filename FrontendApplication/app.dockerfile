FROM nginx:1.10

ADD vhost.conf /etc/nginx/conf.d/default.conf

COPY ./dist /var/www
COPY ./config/config.js.tmpl /etc/nginx/templates/config.js.tmpl
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
