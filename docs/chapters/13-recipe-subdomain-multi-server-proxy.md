# 13. 실전 레시피 A: 멀티 서브도메인 프록시

이 장은 앞에서 배운 내용을 실전 입력값에 맞춰 "완성 가능한 결과물"로 만드는 레시피입니다.  
핵심은 감으로 설정을 쓰는 것이 아니라, 요구사항을 규칙으로 변환하는 절차를 고정하는 것입니다.

## 이 장을 끝내면 할 수 있는 일

1. 서비스 요구사항을 서브도메인 라우팅 규칙으로 변환한다.
2. Traefik 라우터/서비스/미들웨어를 일관된 네이밍으로 구성한다.
3. 멀티 인스턴스 분산과 장애 격리를 검증 가능한 형태로 배포한다.

## 반드시 알아야 할 핵심

- 입력 요구사항을 "도메인, 대상 서비스, 정책" 3요소로 분해하면 구현 실수가 급감한다.

## 레시피 입력 예시 (요구사항)

아래와 같은 요청이 들어왔다고 가정합니다.

1. `app.localhost`는 웹 프론트엔드로 보낸다.
2. `api.localhost`는 API 서버로 보내고, 인스턴스 3대로 분산한다.
3. `admin.localhost`는 관리자 서비스로 보내고, 인증 체인을 붙인다.
4. 모든 라우트에 공통 보안 체인(`default-chain@file`)을 적용한다.

## 1단계: 요구사항을 라우팅 명세로 변환

먼저 구현 전에 명세 표를 만듭니다.

| Host | Router 이름 | Service 이름 | 인스턴스 | 미들웨어 |
|---|---|---|---|---|
| app.localhost | `app-router` | `app-svc` | 1 | `default-chain@file` |
| api.localhost | `api-router` | `api-svc` | 3 | `default-chain@file` |
| admin.localhost | `admin-router` | `admin-svc` | 1 | `admin-chain@file` |

이 표가 배포/검증/롤백의 기준 문서가 됩니다.

## 2단계: 네이밍 규칙 고정

권장 규칙:
1. Router: `<domain>-router`
2. Service: `<domain>-svc`
3. Middleware chain: `<domain>-chain`

예:
1. `api-router`, `api-svc`
2. `admin-router`, `admin-chain`

효과:
1. 대시보드/로그에서 추적이 쉬움
2. 팀 내 커뮤니케이션 비용 감소

## 3단계: Compose 구성

아래 예시는 실습용으로 `traefik/whoami`를 사용합니다.  
실서비스에서는 이미지/포트만 교체하면 동일 패턴으로 적용됩니다.

```yaml
services:
  traefik:
    image: traefik:v3.0
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/etc/traefik/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --api.dashboard=true
      - --api.insecure=true
      - --accesslog=true
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik-lab/dynamic:/etc/traefik/dynamic:ro

  app:
    image: traefik/whoami:v1.10
    labels:
      - traefik.enable=true
      - traefik.http.routers.app-router.rule=Host(`app.localhost`)
      - traefik.http.routers.app-router.entrypoints=web
      - traefik.http.routers.app-router.service=app-svc
      - traefik.http.routers.app-router.middlewares=default-chain@file
      - traefik.http.services.app-svc.loadbalancer.server.port=80

  api:
    image: traefik/whoami:v1.10
    labels:
      - traefik.enable=true
      - traefik.http.routers.api-router.rule=Host(`api.localhost`)
      - traefik.http.routers.api-router.entrypoints=web
      - traefik.http.routers.api-router.service=api-svc
      - traefik.http.routers.api-router.middlewares=default-chain@file
      - traefik.http.services.api-svc.loadbalancer.server.port=80

  admin:
    image: traefik/whoami:v1.10
    labels:
      - traefik.enable=true
      - traefik.http.routers.admin-router.rule=Host(`admin.localhost`)
      - traefik.http.routers.admin-router.entrypoints=web
      - traefik.http.routers.admin-router.service=admin-svc
      - traefik.http.routers.admin-router.middlewares=admin-chain@file
      - traefik.http.services.admin-svc.loadbalancer.server.port=80
```

중요:
1. 스케일 대상(`api`)에는 `container_name`을 지정하지 않습니다.
2. `admin-chain@file`은 `dynamic.yml`에 정의해야 합니다.

## 4단계: File provider 체인 추가

`examples/traefik-lab/dynamic/dynamic.yml` 예시:

```yaml
http:
  middlewares:
    admin-auth:
      basicAuth:
        users:
          - "ops:$apr1$example$hashed-password"

    admin-chain:
      chain:
        middlewares:
          - admin-auth
          - security-headers
          - rate-limit
```

## 5단계: 인스턴스 확장

요구사항대로 API를 3개 인스턴스로 확장합니다.

```bash
cd /path/to/traefik-book
docker compose -f examples/docker-compose.yml up -d --scale api=3
```

## 6단계: 기능 검증 (필수)

## A. 기본 라우팅 확인

```bash
curl -H 'Host: app.localhost' http://localhost
curl -H 'Host: api.localhost' http://localhost
curl -H 'Host: admin.localhost' http://localhost
```

## B. API 분산 확인

```bash
for i in {1..10}; do
  curl -s -H 'Host: api.localhost' http://localhost | grep -i hostname
done
```

## C. 관리자 인증 확인

```bash
curl -i -H 'Host: admin.localhost' http://localhost
curl -i -u ops:yourpassword -H 'Host: admin.localhost' http://localhost
```

## D. 대시보드 확인

- `http://localhost:8080/dashboard/`

확인 포인트:
1. `app-router`, `api-router`, `admin-router` 존재
2. `api-svc`에 서버 인스턴스가 여러 개로 보이는지
3. `admin-router`에 `admin-chain@file` 적용 여부

## 7단계: 장애 주입 테스트

운영 투입 전 최소 1회는 장애 주입을 수행합니다.

```bash
docker ps --format '{{.Names}}' | grep api | head -n 1 | xargs docker stop
for i in {1..10}; do
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: api.localhost' http://localhost
done
```

기대:
1. 일부 인스턴스 중지 후에도 `api.localhost`가 계속 응답
2. 다른 도메인(`app`, `admin`)은 영향 없음

## 8단계: 운영 배포 체크

배포 전 최소 기준:
1. `docker compose ... config` 통과
2. 핵심 Host 3개 smoke test 통과
3. 롤백 커밋/태그 준비
4. 에러율 알림 기준(4xx/5xx) 설정

## 트러블슈팅

1. 한 도메인만 404
- 원인: 해당 router rule 오탈자, Host 헤더 누락
- 조치: Dashboard와 `rawdata`에서 rule 문자열 확인

2. API가 분산되지 않음
- 원인: 스케일 실패, `container_name` 충돌
- 조치: 스케일 대상 서비스에서 `container_name` 제거 후 재기동

3. admin 인증 미적용
- 원인: `admin-chain@file` 미정의 또는 참조명 불일치
- 조치: `dynamic.yml` 키 이름과 router 설정 일치 확인

4. 일부 요청 502
- 원인: 백엔드 인스턴스 down, 포트 설정 오류
- 조치: `loadbalancer.server.port` 및 컨테이너 상태 확인

## 최종 산출물 체크리스트

1. 요구사항 명세 표
2. compose 라우팅 라벨
3. file provider 미들웨어 체인
4. 검증 명령 스크립트
5. 장애 주입 결과 기록

## 요약

1. 멀티 서브도메인 프록시는 "요구사항 -> 명세표 -> 라벨/체인 -> 검증" 순서로 구현해야 안정적이다.
2. 핵심은 라우팅 성공 자체가 아니라, 분산/인증/격리가 동시에 만족되는지 확인하는 것이다.
3. 이 레시피를 팀 표준 템플릿으로 고정하면 신규 서비스 추가 속도가 크게 빨라진다.
4. 다음 장에서는 이 패턴을 Path 게이트웨이 + Proxy Chaining 결합 시나리오로 확장한다.

## 다음 챕터

- [14. 실전 레시피 B: Path 게이트웨이 + 프록시 체이닝](./14-recipe-path-gateway-and-proxy-chaining.md)
