FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir fastapi uvicorn

COPY main.py .

EXPOSE 8000

# 🌟 [502 에러 해결] 프록시 헤더 인식 기능과 타임아웃 불일치 방지 옵션을 추가합니다.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]