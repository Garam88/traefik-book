# traefik-lab

`examples/traefik-lab`은 핸드북 실습을 위한 최소 실행 환경입니다.

## 실행

프로젝트 루트(`traefik-book`)에서 아래 명령을 실행합니다.

```bash
docker compose -f examples/docker-compose.yml up -d
```

## 검증

대시보드:

```bash
# macOS
open http://localhost:8080/dashboard/
# Linux
# xdg-open http://localhost:8080/dashboard/
```

샘플 서비스 라우팅:

```bash
curl -H 'Host: whoami.localhost' http://localhost
```

## 중지

```bash
docker compose -f examples/docker-compose.yml down
```

## 참고

- 현재 구성은 로컬 학습용입니다.
- `api.insecure=true` 설정은 운영 환경에서 사용하면 안 됩니다.
- 미들웨어 체인은 `dynamic/dynamic.yml`에서 관리합니다.
