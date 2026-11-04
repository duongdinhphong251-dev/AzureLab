FROM nginxinc/nginx-unprivileged:1.28-alpine
ENV BACKEND_HOST=backend BACKEND_PORT=8080
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY src/ /usr/share/nginx/html/
EXPOSE 8080
