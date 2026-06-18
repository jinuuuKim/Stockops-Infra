# 1. 다운로드 제한이 덜하고 안정적인 도커 허브의 공식 Amazon Linux 2023 순정 이미지 사용
FROM amazonlinux:2023

# 2. 작업 디렉터리 설정
WORKDIR /app

# 3. Python 3.12 및 패키지 관리자(pip) 설치
RUN dnf install -y python3.12 python3.12-pip && \
    dnf clean all

# 4. PostgreSQL 18 공식 저장소 수동 생성
RUN echo "[pgdg18]" > /etc/yum.repos.d/pgdg18.repo && \
    echo "name=PostgreSQL 18" >> /etc/yum.repos.d/pgdg18.repo && \
    echo "baseurl=https://download.postgresql.org/pub/repos/yum/18/redhat/rhel-9-x86_64" >> /etc/yum.repos.d/pgdg18.repo && \
    echo "enabled=1" >> /etc/yum.repos.d/pgdg18.repo && \
    echo "gpgcheck=0" >> /etc/yum.repos.d/pgdg18.repo

# 5. postgresql18 클라이언트 빌드 패키지 및 백업 의존성 설치
RUN dnf install -y postgresql18 gzip bash && \
    dnf clean all

# 6. pg_dump 실행 파일 경로 및 환경 변수 PATH 설정
ENV PATH="/usr/pgsql-18/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

# 7. (변경점) Azure Blob Storage 라이브러리 설치
RUN pip3.12 install --no-cache-dir azure-storage-blob

# 8. 파이썬 코드 복사
COPY app.py /app/app.py

# 9. 컨테이너 시작 시 실행될 진입 명령
CMD [ "python3.12", "/app/app.py" ]