# 07. 게이트웨이 미들웨어: StripPrefix, Rewrite, 정책 적용

06장에서 경로 기반 라우팅을 만들었다면, 이제는 "백엔드가 실제로 이해하는 URL"로 요청을 변환해야 합니다.  
이 장의 핵심은 라우팅 다음 단계인 미들웨어 체인을 안정적으로 설계하는 것입니다.

## 이 장을 끝내면 할 수 있는 일

1. `StripPrefix`, `ReplacePath`, `ReplacePathRegex`의 용도를 구분해 적용한다.
2. 경로 변환과 보안/제한 정책을 체인으로 설계한다.
3. "매칭은 성공했지만 백엔드에서 404" 같은 문제를 미들웨어 관점에서 진단한다.

## 반드시 알아야 할 핵심

- `StripPrefix`와 `ReplacePath`는 목적이 다르며, 잘못 쓰면 정상 라우팅도 즉시 404가 된다.

## 미들웨어가 필요한 이유

게이트웨이 URL과 백엔드 URL은 보통 다릅니다.

예:
1. 외부 요청: `/auth/login`
2. 백엔드 기대 경로: `/login`

이때 라우터만으로는 해결되지 않고, 미들웨어로 URL을 변환해야 합니다.

## 미들웨어 체인 실행 순서

Traefik은 라우터에 선언된 순서대로 미들웨어를 적용합니다.  
순서가 바뀌면 결과도 바뀝니다.

권장 순서(게이트웨이 기준):
1. 경로 변환 (`StripPrefix`/`ReplacePath`)
2. 보안 정책(헤더/인증)
3. 보호 정책(rate-limit 등)

## URL 변환 미들웨어 선택 기준

| 미들웨어 | 언제 사용 | 결과 |
|---|---|---|
| `StripPrefix` | 앞 경로만 제거하고 나머지는 유지 | `/auth/login` -> `/login` |
| `ReplacePath` | 경로 전체를 고정 값으로 교체 | `/anything` -> `/login` |
| `ReplacePathRegex` | 정규식 규칙으로 동적 치환 | `/v1/users/123` -> `/users/123` |

실무 기본값:
1. 대부분의 게이트웨이 API는 `StripPrefix`로 충분
2. 고정 엔드포인트 리라이트는 `ReplacePath`
3. 복잡한 버전/레거시 매핑은 `ReplacePathRegex`

## 설정 예시 1: StripPrefix

상황:
- 외부: `/auth/*`
- 백엔드: `/*`

File provider 예시(`dynamic.yml`):

```yaml
http:
  middlewares:
    auth-strip:
      stripPrefix:
        prefixes:
          - "/auth"
```

라우터 연결(File provider):

```yaml
http:
  routers:
    gw-auth-router:
      rule: "Host(`gateway.localhost`) && PathPrefix(`/auth`)"
      entryPoints: ["web"]
      service: gw-auth-svc
      middlewares: ["auth-strip", "default-chain"]
```

검증:

```bash
curl -H 'Host: gateway.localhost' http://localhost/auth/login
```

기대 결과:
1. 라우터는 `/auth/login`으로 매칭
2. 백엔드로는 `/login` 전달

## 설정 예시 2: ReplacePath

상황:
- 외부 경로가 다양해도 내부는 항상 `/internal/ping`만 호출하고 싶다.

```yaml
http:
  middlewares:
    force-ping:
      replacePath:
        path: "/internal/ping"
```

사용 시 주의:
1. 모든 요청 경로가 동일 path로 바뀌므로 적용 범위를 라우터 단위로 매우 좁게 제한
2. 디버깅 시 "왜 경로가 사라졌는지" 혼동이 많으므로 로그와 함께 사용

## 설정 예시 3: ReplacePathRegex

상황:
- `/v1/orders/123` -> `/orders/123` 변환

```yaml
http:
  middlewares:
    strip-version:
      replacePathRegex:
        regex: "^/v[0-9]+/(.*)"
        replacement: "/$1"
```

주의:
1. 정규식 오탈자 리스크가 높음
2. 팀 공통 규칙 없이 과사용하면 유지보수가 급격히 어려워짐

## 공통 정책 체인 설계

현재 저장소의 기본 정책 체인:
- `default-chain` (`gzip`, `security-headers`, `rate-limit`)

게이트웨이에서는 아래처럼 "경로별 변환 + 공통 정책"을 결합하는 것이 안전합니다.

```yaml
http:
  middlewares:
    auth-strip:
      stripPrefix:
        prefixes:
          - "/auth"

    auth-chain:
      chain:
        middlewares:
          - auth-strip
          - gzip
          - security-headers
          - rate-limit
```

라우터:

```yaml
http:
  routers:
    gw-auth-router:
      middlewares: ["auth-chain"]
```

## 라우팅/변환 검증 절차

## 1) 케이스별 요청 실행

```bash
curl -i -H 'Host: gateway.localhost' http://localhost/auth/health
curl -i -H 'Host: gateway.localhost' http://localhost/api/health
```

## 2) 응답 헤더 확인

보안 헤더가 들어오는지 확인:

```bash
curl -I -H 'Host: gateway.localhost' http://localhost/auth/health
```

## 3) 로그에서 경로/상태 점검

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

확인 포인트:
1. 라우터 매칭 여부
2. 미들웨어 적용 오류 여부
3. upstream 응답 상태 코드 패턴

## 자주 발생하는 실수

1. `StripPrefix`를 두 번 적용
- 증상: `/auth/login`이 `/login`을 넘어 빈 path처럼 처리되어 404
- 조치: 체인 중복 선언 제거

2. `ReplacePath`를 광범위 라우터에 적용
- 증상: 모든 엔드포인트가 같은 경로로 바뀜
- 조치: 범위를 좁힌 라우터로 분리 적용

3. 라우팅은 맞는데 백엔드에서 404
- 원인: 변환 전/후 경로 기대치 불일치
- 조치: 백엔드 라우트 표와 게이트웨이 변환 규칙을 1:1 매핑 문서화

4. `middleware ... does not exist`
- 원인: 파일 미로딩 또는 이름 오탈자
- 조치: `dynamic.yml` 키 이름과 라우터 참조 문자열 일치 확인

## 운영 적용 가이드

1. 미들웨어 이름 규칙을 표준화한다.
- 예: `<service>-strip`, `<service>-rewrite`, `<service>-chain`
2. 경로 변환 규칙은 문서와 테스트를 동시에 관리한다.
3. 정규식 기반 변환은 최소화하고 리뷰 기준을 높인다.
4. 정책 체인은 공통 체인 + 서비스 체인으로 2계층 분리한다.

## 요약

1. 게이트웨이의 품질은 라우팅보다 "경로 변환 정확성"에서 자주 무너진다.
2. `StripPrefix`는 prefix 제거, `ReplacePath`는 전체 교체로 목적이 다르다.
3. 체인 순서를 고정하고 로그로 검증하면 미들웨어 문제를 빠르게 해결할 수 있다.
4. 다음 장에서는 특정 요청을 다른 프록시로 넘기는 Proxy Chaining을 다룬다.

## 다음 챕터

- [08. 특정 요청을 다른 프록시로 전달하기 (Proxy Chaining)](./08-forwarding-to-another-proxy.md)
