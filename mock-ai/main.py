from fastapi import FastAPI

app = FastAPI()

# ALB의 경로 기반 상태 검사 및 실트래픽을 수용하기 위해 라우트를 개방합니다.
@app.get("/ai")
@app.get("/ai/")
def read_root():
    return {"status": "UP", "ai": "FastAPI AI Mock Success"}