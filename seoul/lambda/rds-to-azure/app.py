import os
import sys
import subprocess
from datetime import datetime
from azure.storage.blob import BlobServiceClient

def run_backup():
    # 1. 환경 변수 로드 및 검증
    try:
        db_host = os.environ['DB_HOST']
        db_port = os.environ.get('DB_PORT', '5432')
        db_user = os.environ['DB_USER']
        db_name = os.environ['DB_NAME']
        db_password = os.environ['DB_PASSWORD']
        
        # Azure 관련 환경 변수로 변경
        azure_conn_str = os.environ['AZURE_CONNECTION_STRING']
        azure_container = os.environ['AZURE_CONTAINER_NAME']
    except KeyError as e:
        print(f"[{datetime.now()}] [ERROR] 필수 환경 변수가 누락되었습니다: {e}")
        sys.exit(1)
    
    # Azure 폴더명 (지정하지 않으면 컨테이너 루트에 저장)
    azure_folder = os.environ.get('AZURE_FOLDER_NAME', '').strip()

    # 2. 파일 경로 및 백업 파일명 설정
    date_suffix = datetime.now().strftime('%Y%m%d_%H%M')
    filename = f"{db_name}_backup_{date_suffix}.sql.gz"
    local_backup_file = f"/tmp/{filename}"

    print(f"[{datetime.now()}] [INFO] RDS PostgreSQL 18 백업 시작: {db_name}")
    os.environ['PGPASSWORD'] = db_password
    
    # 3. pg_dump 및 gzip 압축 실행
    dump_cmd = f"set -o pipefail; pg_dump -h {db_host} -p {db_port} -U {db_user} -d {db_name} | gzip > {local_backup_file}"
    
    try:
        subprocess.run(dump_cmd, shell=True, check=True, executable='/bin/bash')
        print(f"[{datetime.now()}] [INFO] 로컬 덤프 파일 생성 완료: {local_backup_file}")
    except subprocess.CalledProcessError as e:
        print(f"[{datetime.now()}] [ERROR] pg_dump 실행 중 오류가 발생했습니다: {e}")
        sys.exit(1)

    # 4. Azure Blob Storage 업로드 경로 조합 및 전송
    print(f"[{datetime.now()}] [INFO] Azure 업로드 시작 -> 컨테이너: {azure_container}")
    try:
        if azure_folder:
            if not azure_folder.endswith('/'):
                azure_folder += '/'
            blob_name = f"{azure_folder}{filename}"
        else:
            blob_name = filename 
        
        # Azure Blob 클라이언트 생성 및 업로드
        blob_service_client = BlobServiceClient.from_connection_string(azure_conn_str)
        blob_client = blob_service_client.get_blob_client(container=azure_container, blob=blob_name)
        
        with open(local_backup_file, "rb") as data:
            blob_client.upload_blob(data, overwrite=True)
            
        print(f"[{datetime.now()}] [INFO] Azure Blob 업로드 완료: {blob_name}")
    except Exception as e:
        print(f"[{datetime.now()}] [ERROR] Azure 업로드 중 오류가 발생했습니다: {e}")
        sys.exit(1)
    finally:
        # 5. 로컬 /tmp 임시 파일 안전하게 제거
        if os.path.exists(local_backup_file):
            os.remove(local_backup_file)
            print(f"[{datetime.now()}] [INFO] 임시 스토리지 파일 정리 완료.")

if __name__ == "__main__":
    run_backup()
    print(f"[{datetime.now()}] [INFO] 데이터베이스 백업 태스크가 성공적으로 종료되었습니다.")
    sys.exit(0)