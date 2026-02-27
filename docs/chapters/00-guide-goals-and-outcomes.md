# 00. 가이드 목표와 완성 시나리오

이 가이드는 Traefik을 "설정 문법"이 아니라 "요청을 목적지로 정확히 보내는 설계 도구"로 익히는 데 초점을 둡니다.  
학습의 끝은 단순 데모 실행이 아니라, 실제 요구사항을 라우팅 규칙으로 바꿔 배포하고 검증하는 능력입니다.

## 이 책을 보면 할 수 있어야 하는 일

1. 서브도메인 기반 리버스 프록시 구성
- `app.example.com`, `api.example.com`, `admin.example.com` 요청을 각기 다른 서버로 분기한다.

2. Path 게이트웨이 구성
- `example.com/api`, `example.com/auth`, `example.com/billing`을 서비스별로 라우팅한다.

3. 특정 요청의 프록시 체이닝(상위 프록시 전달)
- 일부 요청(예: `/legacy/*`, 특정 Host)을 다른 프록시로 그대로 전달한다.

## 핵심 개념 정리: 프록시 vs 게이트웨이

- 리버스 프록시
클라이언트 대신 백엔드와 통신하고, Host/Path/헤더 조건에 따라 목적지를 선택한다.

- API 게이트웨이
여러 서비스 앞단에 공통 진입점(단일 도메인)을 두고, 경로 정책, 인증, 제한, 로깅을 중앙화한다.

- 프록시 체이닝
Traefik이 최종 애플리케이션 대신 다른 프록시를 upstream으로 호출한다.  
조직 경계, 레거시 시스템, 외부망 연동에서 자주 사용한다.

핵심 포인트는 "기능 차이"보다 "운영 책임 차이"입니다.
- 프록시는 분기에 강하다.
- 게이트웨이는 공통 정책에 강하다.
- 체이닝은 네트워크/조직 경계를 연결하는 데 강하다.

## 이 책의 범위

다룹니다.
1. Traefik v3 기준 라우팅 구성
2. Docker/File Provider 기반 설정 관리
3. Host/Path 규칙 설계와 우선순위
4. 미들웨어 적용(경로 변경, 보안 헤더, 속도 제한)
5. 상위 프록시 전달 구조
6. 운영 전 점검(로그, 디버깅, TLS 기본)

다루지 않습니다.
1. 서비스 메시 상세(Envoy/Istio 심화)
2. OAuth/OIDC 서버 구축 자체
3. 대규모 멀티 리전 네트워크 설계 심화

## 완성 아키텍처(목표 상태)

```mermaid
flowchart LR
  C["Client"] --> T["Traefik (Edge)"]
  T -->|Host(app.example.com)| A["app-service"]
  T -->|Host(api.example.com)| API["api-service"]
  T -->|Host(admin.example.com)| ADM["admin-service"]
  T -->|PathPrefix(/api)| API2["api-gateway-service"]
  T -->|PathPrefix(/auth)| AUTH["auth-service"]
  T -->|PathPrefix(/legacy)| UP["upstream proxy"]
  UP --> LEG["legacy backend"]
```

위 구조에서 중요한 것은 한 번의 진입점에서 세 가지 요구를 동시에 다루는 것입니다.
1. Host 기반 분기
2. Path 분기
3. 조건부 외부 프록시 전달

## 실습 환경 전제

1. Docker / Docker Compose 사용 가능
2. 로컬 포트 `80`, `443`, `8080` 사용 가능
3. 테스트용 로컬 도메인(`*.localhost` 또는 `/etc/hosts`) 사용
4. 저장소 루트에서 `make compose-up` 실행 가능

초기 검증 명령:

```bash
curl -H 'Host: whoami.localhost' http://localhost
```

## 학습 방식

각 챕터는 같은 루프로 진행합니다.
1. 요구사항을 규칙(Host/Path/priority)로 변환
2. Traefik 설정 작성(라벨 또는 파일)
3. `curl`로 성공 케이스 검증
4. 실패 케이스(충돌/미스매치/루프) 재현 후 수정
5. 운영 체크리스트 반영

## 완료 기준(책 전체)

아래 3개를 직접 구성하고 설명할 수 있으면 완료입니다.

1. 서브도메인 분기 프록시
```bash
curl -H 'Host: app.localhost' http://localhost
curl -H 'Host: api.localhost' http://localhost
```

2. Path 게이트웨이
```bash
curl http://localhost/api/health
curl http://localhost/auth/health
```

3. 상위 프록시 전달
```bash
curl http://localhost/legacy/ping
```

## 다음 챕터에서 할 일

다음 장에서는 Traefik의 핵심 구성요소(EntryPoints, Routers, Services, Middlewares)를 요청 흐름 관점으로 정리합니다.  
특히 "어떤 조건이 라우터를 선택하게 만드는가"와 "우선순위 충돌을 어떻게 피하는가"를 먼저 다룹니다.

## 다음 챕터

- [01. Traefik 핵심 구조: 프록시와 게이트웨이 관점](./01-traefik-core-for-proxy-and-gateway.md)
