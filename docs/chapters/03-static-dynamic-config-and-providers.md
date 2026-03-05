# 03. 설정의 기초: Static, Dynamic, Providers

이 장의 핵심은 "무엇을 어디에 선언해야 하는가"를 명확히 구분하는 것입니다.  
Traefik은 기능이 많은 편이지만, 설정 책임만 정확히 나누면 운영 복잡도가 크게 줄어듭니다.

## 이 장을 끝내면 할 수 있는 일

1. `static`과 `dynamic` 설정의 책임 경계를 설명할 수 있다.
2. Docker/File provider의 선언 방식 차이를 설명할 수 있다.
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
  - --providers.file.directory=/etc/traefik/dynamic
  - --providers.file.watch=true
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

dynamic 설정은 provider에 따라 선언 위치가 다릅니다.
1. Docker provider: 서비스 `labels`
2. File provider: `dynamic.yml`

이 저장소의 실습은 File provider 한 경로(`examples/traefik-lab/dynamic/dynamic.yml`)를 기준으로 진행합니다.

## Provider 이해: Docker vs File

## Docker Provider

선언 위치:
- `docker-compose.yml` 각 서비스의 `labels`

예:

```yaml
services:
  whoami:
    image: traefik/whoami:v1.10
    labels:
      - traefik.enable=true
      - traefik.http.routers.whoami.rule=Host(`whoami.localhost`)
      - traefik.http.routers.whoami.entrypoints=web
      - traefik.http.routers.whoami.service=whoami-svc
      - traefik.http.services.whoami-svc.loadbalancer.server.port=80
```

장점:
1. 서비스 정의와 라우팅 정의를 같은 블록에서 관리할 수 있다.
2. 컨테이너 이벤트(기동/중지/재생성)와 함께 동적으로 반영된다.

주의:
1. 라벨 오탈자가 나면 런타임에서만 드러나는 경우가 있다.
2. 공통 정책 재사용/리뷰 관점에서는 파일 기반 구조보다 분산되기 쉽다.

## File Provider

선언 위치:
- `examples/traefik-lab/dynamic/dynamic.yml`

예:

```yaml
http:
  routers:
    whoami-router:
      rule: "Host(`whoami.localhost`)"
      entryPoints: ["web"]
      service: whoami-svc
      middlewares: ["default-chain"]

  services:
    whoami-svc:
      loadBalancer:
        servers:
          - url: "http://whoami:80"

  middlewares:
    default-chain:
      chain:
        middlewares:
          - gzip
          - security-headers
          - rate-limit
```

장점:
1. 라우터/서비스/정책 선언이 한 파일 트리로 모인다.
2. 코드 리뷰/버전 관리 관점에서 변경 이력이 명확하다.
3. 운영 표준 템플릿으로 재사용하기 쉽다.

주의:
1. YAML 문법 오류 시 일부/전체 로딩이 실패할 수 있다.
2. 참조 이름(`default-chain`)이 정확히 일치해야 한다.

참고:
- Docker/File 중 어떤 방식을 선택해도 되지만, 이 책 실습 예시는 File provider 기준으로 통일합니다.

## 현재 저장소 기준 권장 전략

이 책에서는 아래 원칙으로 진행합니다.

1. 라우터/서비스/미들웨어를 모두 File provider에 둔다.
2. 공통 정책은 체인(`default-chain`)으로 재사용한다.
3. 변경은 `dynamic.yml` 중심으로 수행하고, Git diff로 검증한다.

이 방식은 챕터 04~08에서 규칙이 복잡해져도 유지보수가 쉽습니다.

## Reload 방식 이해하기

Provider별 반영 방식:
1. Docker provider
- 컨테이너/라벨 변경 이벤트 시 동적 구성 갱신

2. File provider
- `--providers.file.watch=true` 활성화 시 파일 변경 감지 후 dynamic 설정 재로딩

운영 포인트:
1. "왜 반영이 안 됐는가"를 볼 때 먼저 `dynamic.yml` 실제 변경 여부를 확인한다.
2. static 항목인지 dynamic 항목인지 구분해야 재시작 여부를 판단할 수 있다.

## 실습: 선언 위치와 반영 확인

## 1단계: 현재 라우팅 상태 확인

```bash
cd /path/to/traefik-book
docker compose -f examples/docker-compose.yml up -d
curl -H 'Host: whoami.localhost' http://localhost
```

## 2단계: File provider 변경 테스트 (미들웨어)

`examples/traefik-lab/dynamic/dynamic.yml`에서 `rate-limit.average`를 `100` -> `50`으로 수정한 뒤 저장합니다.

그 후 logs 확인:

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

기대 결과:
1. file provider reloading 관련 로그 출력
2. 컨테이너 재생성 없이 설정 반영

## 3단계: File provider 변경 테스트 (서비스)

`whoami-svc` URL을 일부러 잘못 수정해 502를 재현한 뒤 원복합니다.

예:
1. `http://whoami:80` -> `http://whoami:8080` (실패 확인)
2. 다시 `http://whoami:80`으로 원복

기대 결과:
1. 재기동 없이 즉시 동작 변화가 반영됨
2. 원복 직후 200 응답으로 복구됨

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

1. `middleware ... does not exist`
- 원인: file provider 미로딩 또는 이름 불일치
- 조치: `dynamic.yml` 경로/키 이름/참조 문자열 재확인

2. 파일을 수정했는데 동작이 그대로임
- 원인: 파일 변경이 실제 마운트 경로에 반영되지 않음, 또는 watch 비활성화
- 조치: 마운트 경로 확인, `--providers.file.watch=true` 확인

3. YAML 수정 후 라우팅이 갑자기 404
- 원인: dynamic 파일 문법 오류
- 조치: 최근 변경분 되돌리고 traefik logs에서 파싱 오류 확인

4. 대시보드에는 라우터가 보이는데 요청이 실패
- 원인: service URL/백엔드 주소 불일치
- 조치: `services.*.loadBalancer.servers.url` 재확인

## Provider 선택 기준 요약

1. 서비스 정의와 라우팅을 한 곳(컨테이너 단위)에서 관리하고 싶다 -> Docker provider
2. Git 기반 리뷰/이력 중심으로 정책/규칙을 중앙 관리하고 싶다 -> File provider
3. 이 책 실습은 일관성을 위해 File provider 기준으로 진행한다

## 요약

1. Static은 Traefik 자체 동작, Dynamic은 요청 처리 로직이다.
2. Docker/File provider는 선언 위치와 반영 방식이 다르다.
3. 이 저장소 기준 dynamic 구성은 File provider 단일 경로로 관리한다.
4. 다음 장(04)부터는 이 원칙을 바탕으로 Host 기반 서브도메인 라우팅을 확장한다.

## 다음 챕터

- [04. 서브도메인 라우팅 1: Host 규칙으로 분기](./04-subdomain-routing-with-host-rules.md)
