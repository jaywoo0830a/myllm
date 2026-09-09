# myLLM Script Runner API 이미지
#   - API 는 저장소에서 server/scripts/*.sh 를 실행하므로 bash 가 필요하다.
#   - 스크립트는 호스트에서 실행되는 것으로 가정해, API 는 컨테이너 내에서
#     /myllm 을 마운트하여 호출한다. (docker-compose.yml 참고)
FROM python:3.11-slim

# bash 필요 (up.sh, down.sh, status_report.sh 등)
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash && rm -rf /var/lib/apt/lists/*

WORKDIR /myllm

# requirements 먼저 복사해 레이어 캐시
COPY scripts/api/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# 소스 복사 (실제 저장소는 마운트로 덮어씀)
COPY scripts/api /myllm/scripts/api

ENV PYTHONPATH=/myllm
EXPOSE 18080

# 컨테이너 시작 시 uvicorn 기동
CMD ["uvicorn", "scripts.api.app:app", "--host", "0.0.0.0", "--port", "18080"]