# 09. 엣지 보안 필수: 인증, 헤더, 속도 제한

이 장에서는 Traefik을 "라우팅 도구"에서 한 단계 더 나아가 "보안 경계(Edge Control Plane)"로 사용합니다.  
핵심은 완벽한 보안이 아니라, 운영에서 반드시 갖춰야 할 최소 보안 기준을 빠르게 적용하는 것입니다.

## 이 장을 끝내면 할 수 있는 일

1. 공개/내부 라우트를 분리하고 각기 다른 보안 정책을 적용한다.
2. 인증(`basicAuth`/`forwardAuth`), 보안 헤더, rate limit를 라우터별로 조합한다.
3. 과도한 노출을 줄이고, 공격면을 좁히는 엣지 보안 기본선을 구축한다.

## 반드시 알아야 할 핵심

- 먼저 "공개/내부 라우트 경계"를 정하고, 그다음에 인증/제한 정책을 올려야 한다.

## 보안 경계 모델

Traefik에서 가장 먼저 결정할 것은 "어떤 경로가 인터넷에 열려 있는가"입니다.

권장 분류:
1. `Public route`
- 외부 사용자 트래픽
- 예: `/api/*`, `/auth/*`

2. `Protected route`
- 운영/파트너/관리자 전용
- 예: `/admin/*`, `/internal/*`

3. `Chain route`
- upstream proxy로 전달되는 특수 트래픽
- 예: `/legacy/*`

원칙:
1. 공개 라우트는 최소 권한 정책(헤더 + rate limit + 필요한 인증)
2. 내부 라우트는 강한 정책(IP 제한 + 인증)
3. 경계가 모호하면 기본값은 차단

## 엣지 보안 최소 세트

실무에서 가장 먼저 적용할 4가지:
1. 인증(Authentication)
2. 보안 헤더(Security headers)
3. 요청 제한(Rate limiting)
4. 접근 허용 범위(IP allow list)

## 1) 인증: basicAuth와 forwardAuth

## basicAuth (운영 엔드포인트에 적합)

간단하고 즉시 적용 가능하지만, 사용자 규모가 커지면 한계가 있습니다.

```yaml
http:
  middlewares:
    ops-basic-auth:
      basicAuth:
        users:
          - "ops:$apr1$example$hashed-password"
```

적합한 대상:
1. 임시 운영 페이지
2. 내부 대시보드
3. 소수 운영자 전용 API

## forwardAuth (조직 인증 시스템 연동에 적합)

외부 인증 서비스(OIDC/SSO 게이트웨이 등)에 인증 판단을 위임합니다.

```yaml
http:
  middlewares:
    org-forward-auth:
      forwardAuth:
        address: "http://auth-proxy:4181/auth"
        trustForwardHeader: true
        authResponseHeaders:
          - "X-Auth-User"
          - "X-Auth-Email"
```

적합한 대상:
1. 사내 계정 체계 연동
2. 감사/권한 추적이 필요한 라우트

## 2) 보안 헤더

현재 저장소의 `default-chain`에도 기본 헤더가 포함되어 있습니다.  
보안 장치로서 최소한 아래는 유지하는 것이 좋습니다.

1. `contentTypeNosniff`
2. `frameDeny`
3. `stsSeconds`(HTTPS 전환 이후)
4. 필요 시 CSP/X-Frame-Options/Referrer-Policy 추가

예시:

```yaml
http:
  middlewares:
    security-headers-strict:
      headers:
        contentTypeNosniff: true
        frameDeny: true
        browserXssFilter: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
```

주의:
1. HSTS는 HTTPS 준비 후 활성화해야 안전합니다(10장에서 확장).
2. 헤더 정책은 서비스 특성(iframe 필요 여부 등)에 맞춰 조정해야 합니다.

## 3) Rate limiting

rate limit는 DDoS 완화 도구가 아니라 "기본 남용 방지 장치"로 생각해야 합니다.

```yaml
http:
  middlewares:
    api-rate-limit:
      rateLimit:
        average: 100
        burst: 50
```

권장:
1. 공개 API에 기본 제한 적용
2. 로그인/인증 엔드포인트는 더 엄격한 제한 별도 적용

## 4) IP allow list

관리용 경로는 IP 제한을 함께 적용합니다.

```yaml
http:
  middlewares:
    internal-ip-allow:
      ipAllowList:
        sourceRange:
          - "10.0.0.0/8"
          - "192.168.0.0/16"
```

주의:
1. 클라우드/LB 환경에서는 실제 클라이언트 IP 인식 체인을 먼저 확인해야 합니다.
2. 프록시 체인이 있는 경우 `X-Forwarded-For` 신뢰 정책을 명확히 해야 합니다.

## 정책 조합 예시 (공개 vs 내부)

File provider 예시:

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

라우터 적용 예시(Docker labels):

```yaml
# public route
- traefik.http.routers.gw-api.rule=Host(`gateway.localhost`) && PathPrefix(`/api`)
- traefik.http.routers.gw-api.middlewares=public-chain@file

# protected route
- traefik.http.routers.gw-admin.rule=Host(`gateway.localhost`) && PathPrefix(`/admin`)
- traefik.http.routers.gw-admin.middlewares=internal-chain@file
```

## 실습 절차

## 1) 미들웨어 추가

`examples/traefik-lab/dynamic/dynamic.yml`에 아래를 추가합니다.
1. `api-rate-limit`
2. `ops-basic-auth` (또는 `forwardAuth`)
3. `internal-ip-allow`
4. `public-chain`, `internal-chain`

## 2) 라우터에 체인 연결

공개 경로와 내부 경로에 서로 다른 체인을 연결합니다.

## 3) 동작 검증

```bash
# 공개 경로 (정상 접근)
curl -i -H 'Host: gateway.localhost' http://localhost/api/health

# 내부 경로 (인증 요구)
curl -i -H 'Host: gateway.localhost' http://localhost/admin/health

# 인증 헤더 포함 재시도 (basicAuth 예시)
curl -i -u ops:yourpassword -H 'Host: gateway.localhost' http://localhost/admin/health
```

## 4) 제한 검증 (rate limit)

```bash
for i in {1..200}; do
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: gateway.localhost' http://localhost/api/health
done | sort | uniq -c
```

429 비율이 관측되면 제한이 동작하는 것입니다.

## 트러블슈팅

1. 인증 미들웨어가 적용되지 않음
- 원인: 라우터에 체인 연결 누락
- 조치: `...routers.<name>.middlewares=` 라벨/설정 확인

2. 내부 경로가 외부에서도 열림
- 원인: IP allow list 미적용 또는 잘못된 source range
- 조치: 체인 적용 여부와 CIDR 재확인

3. 정상 사용자도 429 과다 발생
- 원인: rate limit 값이 실제 트래픽보다 너무 낮음
- 조치: baseline 측정 후 `average/burst` 재조정

4. 프록시/LB 뒤에서 IP 제한이 오작동
- 원인: 실제 클라이언트 IP 대신 중간 프록시 IP 인식
- 조치: 배포 환경의 forwarded header 신뢰 경로 점검

5. 보안 헤더 추가 후 일부 화면 깨짐
- 원인: 헤더 정책이 서비스 특성과 충돌(CSP/iframe)
- 조치: 서비스별로 헤더 정책 분기

## 운영 체크리스트

1. 공개/내부 라우트 분류표가 문서화되어 있는가
2. 내부 라우트에 인증 + IP 제한이 함께 적용되어 있는가
3. 공개 라우트에 최소 rate limit이 적용되어 있는가
4. 보안 헤더 정책이 서비스별로 검증되었는가
5. 대시보드/API 관리 엔드포인트가 외부에 노출되지 않는가

## 요약

1. 엣지 보안은 기능 추가보다 "경계 정의"가 먼저다.
2. 최소 세트는 인증, 헤더, rate limit, IP 제한이다.
3. 공개/내부 라우트에 서로 다른 정책 체인을 적용해야 운영 사고를 줄일 수 있다.
4. 다음 장에서는 이 보안 정책을 HTTPS/TLS 기반으로 강화한다.

## 다음 챕터

- [10. TLS/HTTPS 및 인증서 자동화](./10-tls-and-certificates-with-acme.md)
