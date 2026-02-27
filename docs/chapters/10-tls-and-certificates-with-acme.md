# 10. TLS/HTTPS 및 인증서 자동화

09장에서 엣지 보안 기본선을 만들었다면, 이제 트래픽 자체를 HTTPS로 보호해야 합니다.  
이 장에서는 Traefik에서 TLS 종료, HTTP->HTTPS 강제, ACME 자동 발급/갱신까지 한 번에 정리합니다.

## 이 장을 끝내면 할 수 있는 일

1. HTTP 요청을 HTTPS로 강제 리다이렉트한다.
2. ACME(예: Let's Encrypt)로 인증서를 자동 발급/갱신한다.
3. 인증서 저장 경로/권한/백업 정책을 운영 기준으로 설계한다.

## 반드시 알아야 할 핵심

- TLS 종료 위치를 명확히 정하고, 인증서 저장 전략을 먼저 결정해야 운영 사고를 줄일 수 있다.

## TLS 종료 위치 결정

가장 먼저 정해야 할 질문:
1. TLS를 Traefik에서 종료할 것인가?
2. 뒤쪽 upstream까지 TLS를 유지할 것인가?

이 핸드북의 기본:
1. Edge(Traefik)에서 TLS 종료
2. 내부망은 신뢰 구간으로 보고 HTTP 또는 별도 mTLS 전략 적용

장점:
1. 인증서 관리가 Edge에 집중
2. 라우팅/미들웨어 정책과 TLS 정책을 한 지점에서 통제

주의:
1. 규제/보안 요구가 높으면 Edge-Backend 구간도 TLS(mTLS 포함) 검토

## HTTPS 강제 리다이렉트

TLS를 붙였더라도 HTTP가 열려 있으면 평문 접근이 남습니다.  
반드시 HTTP -> HTTPS 전환을 기본 정책으로 둡니다.

정적 설정(EntryPoint 레벨) 예시:

```yaml
command:
  - --entrypoints.web.address=:80
  - --entrypoints.websecure.address=:443
  - --entrypoints.web.http.redirections.entrypoint.to=websecure
  - --entrypoints.web.http.redirections.entrypoint.scheme=https
```

검증:

```bash
curl -I http://gateway.localhost
```

기대:
1. `301` 또는 `308` 리다이렉트
2. `Location: https://...`

## ACME 자동 발급 기본 구성

Traefik에서는 `certificatesresolvers`로 ACME 발급기를 선언합니다.

Compose command 예시:

```yaml
command:
  - --certificatesresolvers.le.acme.email=ops@example.com
  - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
  - --certificatesresolvers.le.acme.httpchallenge=true
  - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
```

라우터에서 resolver 연결:

```yaml
labels:
  - traefik.http.routers.gw-api.entrypoints=websecure
  - traefik.http.routers.gw-api.tls=true
  - traefik.http.routers.gw-api.tls.certresolver=le
```

핵심:
1. 발급기 선언(`le`)과 라우터 참조(`certresolver=le`) 이름이 일치해야 함
2. `websecure` 엔트리포인트가 열려 있어야 함

## Challenge 방식 선택

## 1) HTTP-01

적합:
1. 인터넷에서 80 포트 접근 가능
2. 일반 단일 도메인 발급

장점:
1. 설정 단순

제약:
1. 와일드카드 인증서 발급 불가

## 2) DNS-01

적합:
1. 와일드카드(`*.example.com`) 필요
2. 80 포트 제약이 있는 환경

장점:
1. 와일드카드 발급 가능

제약:
1. DNS provider API 연동 필요
2. 토큰/권한 관리가 추가됨

운영 기준:
1. 단순 시작: HTTP-01
2. 멀티 서브도메인 운영 확대: DNS-01(+와일드카드)

## 로컬 개발 환경 전략

로컬 `*.localhost`는 공개 CA 발급 대상이 아닙니다.  
개발/문서 실습에서는 아래 두 전략 중 하나를 선택합니다.

1. 로컬에서는 HTTP만 사용하고 TLS는 운영 환경 챕터에서 적용
2. 자체 서명/로컬 CA 인증서(예: mkcert)를 파일 provider로 붙여 HTTPS 동작만 검증

핵심:
1. 로컬에서 ACME 발급을 억지로 시도하지 않는다.
2. 운영/스테이징 도메인에서 ACME를 검증한다.

## 인증서 저장 전략 (`acme.json`)

Traefik ACME 저장 파일은 민감 정보입니다.

권장:
1. 컨테이너 재기동 후에도 유지되는 볼륨 사용
2. 파일 권한 엄격 관리(예: 600)
3. 백업 정책 수립

Compose 예시:

```yaml
services:
  traefik:
    volumes:
      - ./traefik-lab/letsencrypt:/letsencrypt
```

초기 파일 준비(호스트):

```bash
mkdir -p examples/traefik-lab/letsencrypt
touch examples/traefik-lab/letsencrypt/acme.json
chmod 600 examples/traefik-lab/letsencrypt/acme.json
```

운영 포인트:
1. 다중 인스턴스 환경에서는 저장 공유/동기화 전략 필요
2. 인증서 스토리지 분실 시 재발급 폭주/레이트 리밋 위험

## 스테이징 -> 프로덕션 전환

Let's Encrypt는 발급 제한(rate limits)이 있습니다.  
초기 검증은 스테이징 CA로 먼저 수행하는 것이 안전합니다.

스테이징 예시:

```yaml
command:
  - --certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

전환 절차:
1. 스테이징에서 라우터/리다이렉트/갱신 동작 검증
2. 운영 전환 시 `caserver` 제거(또는 프로덕션 URL 사용)
3. 기존 테스트 인증서 캐시 정리 후 재발급 확인

## 실습 절차

## 1) EntryPoint와 HTTPS 리다이렉트 설정

`examples/docker-compose.yml`의 `traefik.command`에 아래를 추가합니다.
1. `websecure` 엔트리포인트
2. `web -> websecure` 리다이렉트
3. ACME resolver 선언

## 2) 라우터 TLS 활성화

대상 라우터에 아래를 선언합니다.
1. `entrypoints=websecure`
2. `tls=true`
3. `tls.certresolver=le`

## 3) 실행 및 로그 확인

```bash
docker compose -f examples/docker-compose.yml up -d
docker compose -f examples/docker-compose.yml logs -f traefik
```

확인 포인트:
1. ACME account 등록 로그
2. 인증서 발급/갱신 로그
3. challenge 실패 여부

## 4) 접속 검증

주의: 아래 도메인은 예시입니다. `*.localhost`에서는 ACME 발급이 되지 않으므로 실제 소유 도메인으로 치환해서 테스트하세요.

```bash
curl -I http://your-domain.example
curl -I https://your-domain.example
```

정상 기준:
1. HTTP는 HTTPS로 리다이렉트
2. HTTPS는 인증서 체인 오류 없이 응답

## 자주 발생하는 문제

1. `Unable to obtain ACME certificate`
- 원인: 도메인 DNS 미전파, challenge 경로 접근 실패
- 조치: DNS/포트 80 접근성/방화벽 확인

2. 인증서 발급이 간헐적으로 실패
- 원인: 레이트 리밋 또는 challenge 응답 경합
- 조치: 스테이징으로 검증 후 전환, 재시도 간격 조정

3. 재시작 후 매번 재발급 시도
- 원인: `acme.json` 볼륨 미영속
- 조치: 영속 볼륨 마운트 및 파일 권한 확인

4. HTTPS는 되는데 일부 브라우저 경고
- 원인: 인증서 CN/SAN 불일치, 중간체인 문제
- 조치: 도메인/인증서 대상 재확인, 발급 로그 점검

5. HSTS 적용 후 접속 장애
- 원인: HTTPS 준비 전 HSTS 활성화
- 조치: HSTS는 안정화 이후 단계적으로 활성화

## 운영 체크리스트

1. HTTP -> HTTPS 강제가 전 라우트에 적용되는가
2. ACME 저장소가 영속/백업되는가
3. 스테이징 검증 후 프로덕션 전환 절차가 문서화됐는가
4. 인증서 만료/갱신 실패 알림이 설정되어 있는가
5. 대시보드/관리 경로는 내부 접근으로 제한되는가

## 요약

1. TLS 운영의 핵심은 "리다이렉트 + 자동발급 + 안전한 저장" 3가지다.
2. 로컬과 운영은 인증서 전략을 분리해 관리해야 한다.
3. ACME는 스테이징 검증 후 프로덕션으로 전환하는 절차가 안전하다.
4. 다음 장에서는 TLS까지 포함된 환경에서 문제를 빠르게 추적하는 관측/디버깅 루틴을 다룬다.

## 다음 챕터

- [11. 관측성/디버깅: 로그, 메트릭, 대시보드](./11-observability-and-debugging.md)
