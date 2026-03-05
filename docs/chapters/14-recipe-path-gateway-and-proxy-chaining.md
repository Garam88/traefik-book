# 14. 실전 레시피 B: Path 게이트웨이 + 프록시 체이닝

이 장은 이 핸드북의 핵심 요구를 하나로 결합하는 최종 레시피입니다.  
단일 도메인 Path 게이트웨이를 유지하면서, 특정 경로만 다른 프록시로 전달하는 구조를 완성합니다.

## 이 장을 끝내면 할 수 있는 일

1. `gateway.localhost`에서 `/api`, `/auth`, `/billing`을 내부 서비스로 분기한다.
2. `/legacy` 경로만 upstream proxy로 체이닝한다.
3. 경로 충돌과 프록시 루프를 사전에 차단하는 규칙으로 배포한다.

## 반드시 알아야 할 핵심

- Path 충돌(`priority`)과 루프 방지(`upstream 경계`)를 동시에 설계해야 한다.

## 레시피 입력 예시 (요구사항)

아래 요구를 구현한다고 가정합니다.

1. 공통 진입점: `gateway.localhost`
2. 내부 서비스:
- `/api/*` -> `api-service`
- `/auth/*` -> `auth-service`
- `/billing/*` -> `billing-service`
3. 체이닝 서비스:
- `/legacy/*` -> `upstream-proxy` -> `legacy-backend`
4. 정책:
- 공통 보안 체인 적용
- `/api/admin`은 인증 필요
- 루프 방지 필수

## 1단계: 경로 명세표 작성

구현 전에 아래 표를 확정합니다.

| Path | Router | Service | Type | Priority | Middleware |
|---|---|---|---|---|---|
| `/api` | `gw-api-router` | `gw-api-svc` | direct | 120 | `api-chain` |
| `/auth` | `gw-auth-router` | `gw-auth-svc` | direct | 120 | `auth-chain` |
| `/billing` | `gw-billing-router` | `gw-billing-svc` | direct | 120 | `billing-chain` |
| `/legacy` | `gw-legacy-router` | `gw-legacy-upstream` | chained | 300 | `legacy-chain` |
| `/api/admin` | `gw-api-admin-router` | `gw-admin-svc` | direct | 220 | `admin-chain` |

핵심:
1. 체이닝 경로(`/legacy`)는 높은 `priority`로 명시
2. 더 구체적인 경로(`/api/admin`)는 `/api`보다 높은 `priority`

## 2단계: 라우팅 규칙 설계

기본 규칙:
1. 모든 라우터에 `Host(gateway.localhost)` 포함
2. 서비스 경계는 `PathPrefix`로 분기
3. 충돌 가능 라우터는 `priority` 명시

예시:

```yaml
http:
  routers:
    gw-api-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/api`)"
      priority: 120

    gw-api-admin-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/api/admin`)"
      priority: 220

    gw-legacy-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/legacy`)"
      priority: 300
```

## 3단계: Compose 서비스 구성 예시

아래는 실습용 최소 구성 예시입니다.

```yaml
services:
  traefik:
    image: traefik:v3.0
    command:
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
      - ./traefik-lab/dynamic:/etc/traefik/dynamic:ro

  api:
    image: traefik/whoami:v1.10

  auth:
    image: traefik/whoami:v1.10

  billing:
    image: traefik/whoami:v1.10

  admin:
    image: traefik/whoami:v1.10

  upstream-proxy:
    image: traefik/whoami:v1.10
```

설명:
1. 라우팅 규칙은 compose 라벨이 아니라 File provider에서 관리
2. direct/chain 경로 모두 `dynamic.yml`에서 선언
3. 실습 단순화를 위해 `upstream-proxy`를 단일 서비스로 두었고, 실전에서는 이 프록시가 `legacy-backend`로 전달합니다.

## 4단계: File provider에 라우팅/체이닝 규칙 추가

`examples/traefik-lab/dynamic/dynamic.yml` 예시:

```yaml
http:
  routers:
    gw-api-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/api`)"
      entryPoints: ["web"]
      service: gw-api-svc
      middlewares: ["api-chain"]
      priority: 120

    gw-auth-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/auth`)"
      entryPoints: ["web"]
      service: gw-auth-svc
      middlewares: ["auth-chain"]
      priority: 120

    gw-billing-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/billing`)"
      entryPoints: ["web"]
      service: gw-billing-svc
      middlewares: ["billing-chain"]
      priority: 120

    gw-api-admin-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/api/admin`)"
      entryPoints: ["web"]
      service: gw-admin-svc
      middlewares: ["admin-chain"]
      priority: 220

    gw-legacy-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/legacy`)"
      entryPoints: ["web"]
      service: gw-legacy-upstream
      middlewares: ["legacy-chain"]
      priority: 300

  middlewares:
    api-strip:
      stripPrefix:
        prefixes: ["/api"]

    auth-strip:
      stripPrefix:
        prefixes: ["/auth"]

    billing-strip:
      stripPrefix:
        prefixes: ["/billing"]

    admin-strip:
      stripPrefix:
        prefixes: ["/api/admin"]

    legacy-strip:
      stripPrefix:
        prefixes: ["/legacy"]

    legacy-retry:
      retry:
        attempts: 2
        initialInterval: 100ms

    api-chain:
      chain:
        middlewares: ["api-strip", "default-chain"]

    auth-chain:
      chain:
        middlewares: ["auth-strip", "default-chain"]

    billing-chain:
      chain:
        middlewares: ["billing-strip", "default-chain"]

    admin-chain:
      chain:
        middlewares: ["admin-strip", "default-chain"]

    legacy-chain:
      chain:
        middlewares: ["legacy-strip", "legacy-retry", "default-chain"]

  services:
    gw-api-svc:
      loadBalancer:
        servers:
          - url: "http://api:80"

    gw-auth-svc:
      loadBalancer:
        servers:
          - url: "http://auth:80"

    gw-billing-svc:
      loadBalancer:
        servers:
          - url: "http://billing:80"

    gw-admin-svc:
      loadBalancer:
        servers:
          - url: "http://admin:80"

    gw-legacy-upstream:
      loadBalancer:
        servers:
          - url: "http://upstream-proxy:80"
        passHostHeader: false
```

## 5단계: 루프 방지 적용

반드시 지킬 규칙:
1. upstream URL이 edge Traefik 자신을 가리키지 않게 설정
2. chain 경로(`/legacy`)를 좁게 고정
3. upstream proxy에 다시 `gateway.localhost/legacy`로 돌아오는 규칙 금지

운영 팁:
1. chain 트래픽 전용 헤더(`X-Proxy-Chain: edge`)를 추가하고, upstream에서 재진입 차단

## 6단계: 실행

```bash
cd /path/to/traefik-book
docker compose -f examples/docker-compose.yml up -d
```

## 7단계: 기능 검증

## A. direct path 검증

```bash
curl -i -H 'Host: gateway.localhost' http://localhost/api/health
curl -i -H 'Host: gateway.localhost' http://localhost/auth/health
curl -i -H 'Host: gateway.localhost' http://localhost/billing/health
curl -i -H 'Host: gateway.localhost' http://localhost/api/admin/health
```

## B. chain path 검증

```bash
curl -i -H 'Host: gateway.localhost' http://localhost/legacy/ping
```

확인:
1. `/legacy`만 upstream 경로로 전달되는지
2. `/api`, `/auth`, `/billing`은 기존 direct 서비스 유지

## C. 충돌 검증

```bash
curl -i -H 'Host: gateway.localhost' http://localhost/api/admin/users
```

확인:
1. `priority`가 높은 admin 라우터로 고정되는지

## D. 대시보드 검증

- `http://localhost:8080/dashboard/`

확인 포인트:
1. `gw-legacy-router` 존재
2. `gw-legacy-upstream`이 `upstream-proxy`로 연결
3. direct 라우터들과 분리되어 표시

## 8단계: 장애 주입 테스트

## 시나리오 A: upstream-proxy down

```bash
docker stop upstream-proxy
curl -i -H 'Host: gateway.localhost' http://localhost/legacy/ping
curl -i -H 'Host: gateway.localhost' http://localhost/api/health
```

기대:
1. `/legacy`는 실패 가능(502/504)
2. `/api`는 정상 유지 (격리 확인)

## 시나리오 B: priority 누락

1. `gw-api-admin-router.priority`를 제거 또는 낮춤
2. `/api/admin/*` 요청 재검증
3. 잘못된 매칭 발생 여부 확인 후 priority 복원

## 트러블슈팅

1. `/legacy`가 404
- 원인: `gw-legacy-router` rule 오탈자/미로딩
- 조치: `rawdata`에서 `router` 존재 여부 확인

2. `/legacy`가 loop처럼 지연
- 원인: upstream이 edge로 재진입
- 조치: upstream URL/규칙 분리, chain 경로 제한

3. `/api`가 `/api/admin`을 먹어버림
- 원인: priority 설계 누락
- 조치: 구체 경로 라우터 priority 상승

4. direct 경로도 함께 장애
- 원인: 공통 미들웨어/체인이 과도하게 결합됨
- 조치: chain 전용 미들웨어와 direct 체인 분리

## 최종 산출물 체크리스트

1. Path 라우팅 명세표(경로/우선순위/대상)
2. direct 라우터/서비스 동적 설정
3. chain 라우터 + upstream 서비스(dynamic.yml)
4. 루프 방지 규칙 문서
5. 검증/장애주입 결과 로그

## 요약

1. Path 게이트웨이 + Proxy Chaining은 "직접 라우팅과 위임 라우팅의 경계 관리"가 핵심이다.
2. 충돌은 `priority`, 루프는 `upstream 경계`로 통제한다.
3. 기능 검증과 장애 주입을 함께 해야 운영 투입이 가능하다.
4. 다음 장(부록)에서는 이 레시피를 재사용할 수 있는 규칙/템플릿으로 정리한다.

## 다음 챕터

- [15. 부록: 규칙 치트시트와 설정 템플릿](./15-appendix-cheatsheets-and-templates.md)
