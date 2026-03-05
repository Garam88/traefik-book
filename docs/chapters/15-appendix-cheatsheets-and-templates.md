# 15. 부록: 규칙 치트시트와 설정 템플릿

이 부록은 앞선 00~14장을 실제 운영에서 빠르게 재사용할 수 있도록 만든 실전 참고 모음입니다.  
설정 문법을 다시 찾는 시간보다, 검증/운영 판단 시간을 줄이는 데 목적이 있습니다.

## 이 부록을 어떻게 쓰면 좋은가

1. 새 라우트 추가 전: `규칙 치트시트` 확인
2. 구성 시작 시: `템플릿` 복붙 후 값만 치환
3. 배포 전: `검증 명령 모음` 실행
4. 장애 시: `상태코드/증상별 원인표`로 1차 분류

## 1) 규칙 문법 치트시트

## Router Rule 기본

```text
Host(`app.example.com`)
Host(`api.example.com`) && PathPrefix(`/v1`)
Host(`gateway.example.com`) && Path(`/healthz`)
```

규칙 선택 기준:
1. 도메인 분기: `Host`
2. 게이트웨이 경로 분기: `PathPrefix`
3. 단일 엔드포인트 분기: `Path`

## 우선순위(Priority) 규칙

기본 원칙:
1. 더 구체적인 규칙에 더 높은 priority
2. 겹칠 가능성이 있으면 priority를 명시

예:

```text
PathPrefix(`/api`)        priority=100
PathPrefix(`/api/admin`)  priority=200
```

## 2) 미들웨어 선택 치트시트

| 목적 | 추천 미들웨어 | 핵심 포인트 |
|---|---|---|
| 경로 앞 prefix 제거 | `StripPrefix` | `/auth/login` -> `/login` |
| 경로 전체 교체 | `ReplacePath` | 모든 요청을 고정 path로 교체 |
| 정규식 경로 치환 | `ReplacePathRegex` | 버전 prefix 제거 등에 사용 |
| 공통 압축 | `compress` | 응답 압축 |
| 보안 헤더 | `headers` | nosniff, frame deny, HSTS |
| 인증 | `basicAuth`/`forwardAuth` | 운영 경로 보호 |
| 요청 제한 | `rateLimit` | 남용 완화 |
| IP 제한 | `ipAllowList` | 내부 경로 제한 |
| 재시도 | `retry` | 체이닝/upstream 불안정 대응 |

## 3) 네이밍 규칙 템플릿

권장 패턴:
1. Router: `<scope>-<svc>-router`
2. Service: `<scope>-<svc>-svc`
3. Middleware: `<scope>-<svc>-<purpose>`

예:
1. `gw-api-router`
2. `gw-api-svc`
3. `gw-api-chain`

## 4) 복붙 템플릿

## A. 서브도메인 분기 (File provider)

```yaml
http:
  routers:
    app-router:
      rule: "Host(`app.example.com`)"
      entryPoints: ["web"]
      service: app-svc
      middlewares: ["default-chain"]

  services:
    app-svc:
      loadBalancer:
        servers:
          - url: "http://app:8080"
```

## B. Path 게이트웨이 분기 (File provider)

```yaml
http:
  routers:
    gw-api-router:
      rule: "Host(`gateway.example.com`) && PathPrefix(`/api`)"
      entryPoints: ["web"]
      priority: 120
      service: gw-api-svc
      middlewares: ["gw-api-chain"]

  services:
    gw-api-svc:
      loadBalancer:
        servers:
          - url: "http://api:8080"
```

## C. Proxy Chaining (File provider)

```yaml
http:
  routers:
    gw-legacy-router:
      rule: "Host(`gateway.example.com`) && PathPrefix(`/legacy`)"
      entryPoints: ["web"]
      service: gw-legacy-upstream
      middlewares: ["legacy-chain"]
      priority: 300

  middlewares:
    legacy-strip:
      stripPrefix:
        prefixes: ["/legacy"]
    legacy-chain:
      chain:
        middlewares: ["legacy-strip", "default-chain"]

  services:
    gw-legacy-upstream:
      loadBalancer:
        servers:
          - url: "http://upstream-proxy:8080"
        passHostHeader: false
```

## D. 보안 체인 (File provider)

```yaml
http:
  middlewares:
    public-chain:
      chain:
        middlewares:
          - security-headers
          - api-rate-limit

    internal-chain:
      chain:
        middlewares:
          - internal-ip-allow
          - ops-basic-auth
          - security-headers-strict
```

## E. HTTPS + ACME (static command)

```yaml
command:
  - --entrypoints.web.address=:80
  - --entrypoints.websecure.address=:443
  - --entrypoints.web.http.redirections.entrypoint.to=websecure
  - --entrypoints.web.http.redirections.entrypoint.scheme=https
  - --certificatesresolvers.le.acme.email=ops@example.com
  - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
  - --certificatesresolvers.le.acme.httpchallenge=true
  - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
```

라우터 TLS 연결:

```yaml
http:
  routers:
    gw-api-router:
      rule: "Host(`gateway.example.com`) && PathPrefix(`/api`)"
      entryPoints: ["websecure"]
      service: gw-api-svc
      tls:
        certResolver: le
```

## 5) 검증 명령 모음

## 기본 상태 확인

```bash
docker compose -f examples/docker-compose.yml config
docker compose -f examples/docker-compose.yml ps
docker compose -f examples/docker-compose.yml logs -f traefik
```

## Host 분기 확인

```bash
curl -H 'Host: app.localhost' http://localhost
curl -H 'Host: api.localhost' http://localhost
curl -H 'Host: admin.localhost' http://localhost
```

## Path 분기 확인

```bash
curl -H 'Host: gateway.localhost' http://localhost/api/health
curl -H 'Host: gateway.localhost' http://localhost/auth/health
curl -H 'Host: gateway.localhost' http://localhost/billing/health
```

## Chain 확인

```bash
curl -H 'Host: gateway.localhost' http://localhost/legacy/ping
```

## Dashboard / `rawdata`

```bash
# macOS
open http://localhost:8080/dashboard/
# Linux
# xdg-open http://localhost:8080/dashboard/
curl -s http://localhost:8080/api/rawdata | jq .
```

## 6) 상태코드/증상별 빠른 원인표

| 증상 | 우선 의심 | 1차 확인 |
|---|---|---|
| 404 | 라우터 미매칭/priority 충돌 | Dashboard rule, `rawdata` router |
| 401/403 | 인증 체인 | router middlewares, auth 설정 |
| 429 | rate limit 과도 | rateLimit average/burst |
| 502 | 업스트림 연결 실패 | service URL/port, 컨테이너 상태 |
| 504 | timeout 미흡/업스트림 지연 | serversTransport timeout |
| TLS 오류 | certresolver/도메인 불일치 | ACME logs, SAN/CN 확인 |
| 지연 급증 | 루프/재시도 과다/업스트림 느림 | access log latency, retry 정책 |

## 7) 롤백 템플릿

```bash
# 안정 설정 복구
git checkout <stable-tag-or-commit> -- examples/docker-compose.yml examples/traefik-lab/dynamic/dynamic.yml

# 재배포
docker compose -f examples/docker-compose.yml up -d

# 핵심 스모크 테스트
curl -I -H 'Host: gateway.localhost' http://localhost/api/health
curl -I -H 'Host: gateway.localhost' http://localhost/auth/health
curl -I -H 'Host: gateway.localhost' http://localhost/legacy/ping
```

## 8) 운영 전 최종 체크리스트

1. 공개/내부/체이닝 경계가 문서화되어 있는가
2. 충돌 가능 라우터에 priority가 명시되어 있는가
3. 미들웨어 체인 이름과 참조가 일치하는가
4. HTTPS 강제와 인증서 저장소 영속이 적용되어 있는가
5. 장애 주입(업스트림 다운/priority 누락) 테스트를 완료했는가
6. 롤백 명령과 안정 태그가 준비되어 있는가
7. 알림(5xx/429/TLS 만료)이 구성되어 있는가

## 9) 파일 위치 인덱스

1. 실행 구성: `examples/docker-compose.yml`
2. 공통 동적 설정: `examples/traefik-lab/dynamic/dynamic.yml`
3. 빠른 실행 명령: `Makefile`
4. 챕터 인덱스: `README.md`, `docs/SUMMARY.md`

## 요약

1. 이 부록은 "재학습용"이 아니라 "즉시 실행용"이다.
2. 새 라우트 추가 시 템플릿 복붙 -> 값 치환 -> 검증 루틴 순서로 작업하면 실수가 크게 줄어든다.
3. 운영 안정성은 멋진 설정보다 일관된 네이밍, 검증, 롤백 준비에서 나온다.
