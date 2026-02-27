# 03. 설정의 기초: Static, Dynamic, Providers

이 장의 핵심은 "무엇을 어디에 선언해야 하는가"를 명확히 구분하는 것입니다.  
Traefik은 기능이 많은 편이지만, 설정 책임만 정확히 나누면 운영 복잡도가 크게 줄어듭니다.

## 이 장을 끝내면 할 수 있는 일

1. `static`과 `dynamic` 설정의 책임 경계를 설명할 수 있다.
2. Docker/File provider를 상황에 맞게 선택할 수 있다.
3. 설정 변경 시 재시작이 필요한지, 실시간 반영되는지 판단할 수 있다.

## 반드시 알아야 할 핵심

- Provider별 선언 위치와 reload(재적용) 방식이 다르다.

## 설정 책임 분리: Static vs Dynamic

Traefik 설정은 크게 두 층으로 나뉩니다.

## 1) Static 설정

Traefik 프로세스 자체의 동작 방식을 정의합니다.

예:
1. EntryPoints(`:80`, `:443`)
2. 어떤 Provider를 사용할지
3. Dashboard/API 활성화
4. 로그 레벨, access log 여부

특징:
1. 일반적으로 프로세스 시작 시 읽는다.
2. 변경 시 재시작이 필요한 경우가 많다.

이 저장소에서 static 설정은 `docker-compose.yml`의 `traefik.command`로 선언되어 있습니다.

```yaml
command:
  - --providers.docker=true
  - --providers.file.directory=/etc/traefik/dynamic
  - --entrypoints.web.address=:80
  - --entrypoints.websecure.address=:443
  - --api.dashboard=true
  - --accesslog=true
```

## 2) Dynamic 설정

라우팅 규칙과 미들웨어처럼 "요청 처리 로직"을 정의합니다.

예:
1. Routers
2. Services
3. Middlewares
4. TLS 라우팅(구성 방식에 따라)

특징:
1. Provider에서 읽는다.
2. 변경이 실시간 반영될 수 있다(Provider 특성에 따름).

이 저장소에서는 dynamic 설정을 두 경로로 함께 사용합니다.
1. Docker labels (`whoami` 서비스)
2. File provider (`examples/traefik-lab/dynamic/dynamic.yml`)

## Provider 이해: Docker vs File

## Docker Provider

선언 위치:
- `docker-compose.yml` 각 서비스의 `labels`

예:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.whoami.rule=Host(`whoami.localhost`)
  - traefik.http.routers.whoami.entrypoints=web
  - traefik.http.routers.whoami.middlewares=default-chain@file
  - traefik.http.services.whoami.loadbalancer.server.port=80
```

장점:
1. 서비스와 라우팅 선언이 한 곳에 모인다.
2. 컨테이너 생성/변경 이벤트로 자동 반영되기 쉽다.

주의:
1. `--providers.docker.exposedbydefault=false`인 경우 `traefik.enable=true`를 반드시 선언해야 한다.
2. 라벨 오탈자는 런타임에 바로 드러나지 않을 수 있어 로그/대시보드 확인이 필요하다.

## File Provider

선언 위치:
- `examples/traefik-lab/dynamic/dynamic.yml`

예:

```yaml
http:
  middlewares:
    default-chain:
      chain:
        middlewares:
          - gzip
          - security-headers
          - rate-limit
```

장점:
1. 공통 정책을 템플릿처럼 재사용하기 좋다.
2. 코드 리뷰/버전 관리 관점에서 변경 이력이 명확하다.

주의:
1. YAML 문법 오류 시 일부/전체 로딩이 실패할 수 있다.
2. 참조 이름(`default-chain@file`)이 정확히 일치해야 한다.

## 현재 저장소 기준 권장 분리 전략

이 책에서는 아래 원칙으로 진행합니다.

1. 서비스별 라우팅은 Docker labels에 둔다.
2. 공통 미들웨어/정책은 File provider에 둔다.
3. 라우터에서 공통 정책을 `@file`로 참조한다.

예:
1. `whoami` 라우터 선언: Docker labels
2. `default-chain` 선언: `dynamic.yml`
3. 연결: `traefik.http.routers.whoami.middlewares=default-chain@file`

이 방식은 챕터 04~08에서 규칙이 복잡해져도 유지보수가 쉽습니다.

## Reload 방식 이해하기

Provider별 반영 방식:

1. Docker provider
- 컨테이너 시작/중지/라벨 변경 이벤트 시 갱신

2. File provider (`--providers.file.watch=true`)
- 파일 변경 감지 후 dynamic 설정 재로딩

운영 포인트:
1. "왜 반영이 안 됐는가"를 볼 때, 먼저 어떤 Provider 경로인지 확인한다.
2. static 항목인지 dynamic 항목인지 구분해야 재시작 여부를 판단할 수 있다.

## 실습: 선언 위치와 반영 확인

## 1단계: 현재 라우팅 상태 확인

```bash
cd /path/to/traefik-book
docker compose -f examples/docker-compose.yml up -d
curl -H 'Host: whoami.localhost' http://localhost
```

## 2단계: File provider 변경 테스트

`examples/traefik-lab/dynamic/dynamic.yml`에 미들웨어 값을 수정한 뒤 저장합니다.

예:
- `rate-limit.average` 값을 `100` -> `50`으로 변경

그 후 logs 확인:

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

기대 결과:
1. file provider reloading 관련 로그 출력
2. 컨테이너 재생성 없이 설정 반영

## 3단계: Docker provider 변경 테스트

`whoami` 라벨 하나를 수정하고 컨테이너를 재생성합니다.

```bash
docker compose -f examples/docker-compose.yml up -d --force-recreate whoami
```

기대 결과:
1. traefik이 서비스 라우터를 재탐지
2. 대시보드에 변경된 라우팅 정보 반영

## 검증 명령 모음

1. 대시보드:
- `http://localhost:8080/dashboard/`

2. `rawdata` API(로컬 학습용):
- `http://localhost:8080/api/rawdata`

3. 라우팅 검증:

```bash
curl -H 'Host: whoami.localhost' http://localhost
```

## 자주 발생하는 문제와 해결

1. `middleware ...@file does not exist`
- 원인: file provider 미로딩 또는 이름 불일치
- 조치: `dynamic.yml` 경로/키 이름/참조 문자열 재확인

2. 라벨을 수정했는데 동작이 그대로임
- 원인: 대상 컨테이너 재생성이 안 됨
- 조치: `up -d --force-recreate <service>` 또는 전체 재기동

3. YAML 수정 후 라우팅이 갑자기 404
- 원인: dynamic 파일 문법 오류
- 조치: 최근 변경분 되돌리고 traefik logs에서 파싱 오류 확인

4. 대시보드에는 라우터가 보이는데 요청이 실패
- 원인: service 포트/백엔드 주소 불일치
- 조치: `loadbalancer.server.port` 또는 upstream URL 재확인

## Provider 선택 기준 요약

1. 서비스와 라우팅을 함께 관리하고 싶다 -> Docker provider
2. 공통 정책과 재사용 가능한 규칙을 관리하고 싶다 -> File provider
3. 실무에서는 둘을 혼합해 책임 분리하는 것이 가장 안정적이다

## 요약

1. Static은 Traefik 자체 동작, Dynamic은 요청 처리 로직이다.
2. Docker/File provider는 선언 위치와 반영 방식이 다르다.
3. 이 저장소 기준 최적 전략은 "라우터/서비스는 Docker, 공통 미들웨어는 File"이다.
4. 다음 장(04)부터는 이 분리 원칙을 바탕으로 Host 기반 서브도메인 라우팅을 확장한다.

## 다음 챕터

- [04. 서브도메인 라우팅 1: Host 규칙으로 분기](./04-subdomain-routing-with-host-rules.md)
