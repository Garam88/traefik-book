# 02. 실습 환경 준비: 도메인/네트워크/Docker

이 장의 목적은 "Traefik 설정을 쓰기 전에 실습 기반을 안정적으로 고정"하는 것입니다.  
이 단계가 불안정하면 이후 챕터(서브도메인 라우팅, Path 게이트웨이, Proxy Chaining)에서 문제 원인을 구분하기 어렵습니다.

## 이 장을 끝내면 할 수 있는 일

1. 로컬 도메인(`*.localhost` 또는 `hosts`)을 Traefik 테스트에 맞게 구성한다.
2. Docker Compose로 Traefik + 테스트 백엔드를 실행하고 네트워크 연결을 확인한다.
3. 포트 충돌 상황에서도 환경 변수로 실습 포트를 조정해 계속 진행한다.

## 반드시 알아야 할 핵심

- `hosts` 설정과 포트 설계가 라우팅 검증의 전제다.

## 준비물 체크

아래 4개가 준비되어야 합니다.

1. Docker Engine / Docker Compose 사용 가능
2. `curl` 사용 가능
3. `make` 사용 가능 (없으면 `docker compose` 직접 실행)
4. 저장소 경로: `traefik-book`

권장 사전 점검:

```bash
docker --version
docker compose version
curl --version
```

## 현재 실습 구성 이해하기

이 저장소의 기본 실습 파일:
- `examples/docker-compose.yml`

핵심 서비스:
1. `traefik`  
포트 `80`, `443`, `8080` 노출, Docker/File provider 활성화
2. `whoami`  
`Host(whoami.localhost)` 규칙으로 라우팅되는 테스트 백엔드

의미:
- `whoami.localhost` 요청이 Traefik을 통과해 백엔드로 전달되면 실습 기반이 정상입니다.

## 포트 설계 기준

기본 포트:
1. HTTP: `80` -> Traefik `web`
2. HTTPS: `443` -> Traefik `websecure`
3. Dashboard: `8080`

Compose는 환경 변수로 포트를 바꿀 수 있게 되어 있습니다.

```yaml
ports:
  - "${TRAEFIK_HTTP_PORT:-80}:80"
  - "${TRAEFIK_HTTPS_PORT:-443}:443"
  - "${TRAEFIK_DASHBOARD_PORT:-8080}:8080"
```

포트 충돌 시 예시:

```bash
TRAEFIK_HTTP_PORT=18080 TRAEFIK_HTTPS_PORT=18443 TRAEFIK_DASHBOARD_PORT=18081 \
docker compose -f examples/docker-compose.yml up -d
```

운영 팁:
1. 문서/스크립트는 기본 포트 기준으로 유지
2. 로컬 개인 환경에서만 환경 변수로 오버라이드

## 도메인 해석 전략: localhost vs hosts

## 1) 추천: `*.localhost` 사용

현대 브라우저/OS에서는 `something.localhost`가 루프백으로 해석되는 경우가 많아 실습에 편리합니다.

예:
- `whoami.localhost`
- `app.localhost`
- `api.localhost`

## 2) 필요 시: `/etc/hosts` 사용

환경에 따라 서브도메인 해석이 다를 수 있으므로 확실히 고정하고 싶다면 `hosts`를 사용합니다.

```bash
sudo sh -c 'cat >> /etc/hosts <<EOF
127.0.0.1 whoami.localhost app.localhost api.localhost admin.localhost gateway.localhost
EOF'
```

검증:

```bash
ping -c 1 whoami.localhost
```

주의:
1. 기존 `hosts` 항목과 중복되지 않게 관리
2. 팀 내 공유 시 "필수 도메인 목록"을 문서화

## 실습 진행 절차

## 1단계: 실습 환경 실행

프로젝트 루트에서 실행:

```bash
cd /path/to/traefik-book
make compose-up
```

또는:

```bash
docker compose -f examples/docker-compose.yml up -d
```

컨테이너 확인:

```bash
docker compose -f examples/docker-compose.yml ps
```

기대 결과:
1. `traefik-lab` 컨테이너 실행 중
2. `traefik-whoami` 컨테이너 실행 중

## 2단계: 기본 라우팅 검증

## A. Host 기반 라우팅 확인

```bash
curl -H 'Host: whoami.localhost' http://localhost
```

응답에 요청 헤더/호스트 정보가 보이면 정상입니다.

## B. 대시보드 접근 확인

- 기본: `http://localhost:8080/dashboard/`
- 포트 오버라이드한 경우: 지정한 대시보드 포트 사용

대시보드에서 `whoami` 라우터/서비스가 보이면 준비 완료입니다.

## 3단계: 네트워크/로그 확인

라우팅 실패 시 먼저 로그를 봅니다.

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

확인 포인트:
1. 라우터 인식 여부
2. 요청 매칭 로그
3. upstream 연결 오류(`connection refused`, `no route to host` 등)

## 자주 발생하는 문제와 해결

1. `curl`은 되는데 브라우저가 이상한 페이지를 보여줌
- 원인: 브라우저 캐시/확장 프로그램/프록시 설정
- 조치: 시크릿 모드, 확장 비활성화, `curl` 기준으로 먼저 검증

2. `whoami.localhost`가 해석되지 않음
- 원인: 로컬 DNS 정책 차이
- 조치: `/etc/hosts`에 직접 매핑 후 재검증

3. `bind: address already in use`
- 원인: 80/443/8080 포트 점유
- 조치: 환경 변수로 포트 변경 후 실행

4. 대시보드는 열리는데 라우팅이 404
- 원인: Host 헤더 미설정 요청
- 조치: 테스트 시 반드시 `-H 'Host: ...'` 포함

## 다음 장을 위한 준비 산출물

다음 장(03)에서 static/dynamic 설정을 본격 분리하기 전에 아래가 준비되어 있어야 합니다.

1. 기본 compose 실행/중지 명령
2. Host 라우팅 검증 명령
3. 포트 오버라이드 실행 패턴
4. 트러블슈팅 기준 로그 확인 명령

## 요약

1. 실습 성공의 핵심은 라우팅 규칙 이전에 네트워크/도메인/포트 전제를 고정하는 것이다.
2. `whoami.localhost` 검증이 통과하면 이후 챕터의 설정 실험을 안전하게 진행할 수 있다.
3. 포트 충돌과 도메인 해석 이슈는 환경 변수와 `hosts`로 빠르게 우회 가능하다.
4. 문제 발생 시 대시보드보다 먼저 `curl + traefik logs`로 사실관계를 확인한다.

## 다음 챕터

- [03. 설정의 기초: Static, Dynamic, Providers](./03-static-dynamic-config-and-providers.md)
