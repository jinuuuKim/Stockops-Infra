FROM nginx:alpine
# Nginx 가동 포트를 8080으로 변경합니다.
RUN sed -i 's/listen       80;/listen       8080;/g' /etc/nginx/conf.d/default.conf
# [교정] api 디렉터리를 만들고, 그 하위의 api/index.html 경로에 정확히 마크다운을 바인딩합니다.
RUN mkdir -p /usr/share/nginx/html/api && echo "<h1>🚀 StockOps Backend API (React Mock) Success!</h1>" > /usr/share/nginx/html/api/index.html
EXPOSE 8080