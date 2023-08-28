#FROM nginx:alpine
FROM --platform=linux/amd64 nginx:alpine
COPY ./index.html /usr/share/nginx/html/index.html
