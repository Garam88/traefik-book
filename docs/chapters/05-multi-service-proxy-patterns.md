# 05. 서브도메인 라우팅 2: 다중 서버 프록시 패턴

04장에서 "서브도메인 1개 -> 서비스 1개" 분기를 만들었다면,  
이 장에서는 같은 서브도메인을 여러 서버 인스턴스로 확장해 운영 가능한 프록시 패턴으로 발전시킵니다.

## 이 장을 끝내면 할 수 있는 일

1. 동일 Host 라우터 뒤에 다중 백엔드 인스턴스를 붙여 로드밸런싱한다.
2. 헬스체크/재시도/sticky 정책의 적용 지점을 구분한다.
3. 특정 서비스 장애가 다른 서브도메인으로 전파되지 않도록 격리 기준을 세운다.

## 반드시 알아야 할 핵심

- 서비스 분리 전략과 장애 격리를 먼저 설계하고, 그 다음에 라우팅 규칙을 붙여야 한다.

## 04장과의 차이

04장은 "분기 정확성"이 목표였습니다.
1. `app.localhost` -> app
2. `api.localhost` -> api
3. `admin.localhost` -> admin

05장은 "확장 내구성"이 목표입니다.
1. 같은 `api.localhost` 요청을 여러 API 인스턴스로 분산
2. 일부 인스턴스 장애 시 나머지로 계속 서비스
3. 한 서비스 장애가 다른 도메인 라우트에 영향 주지 않도록 구조화

## 패턴 A: 동일 Host + 다중 인스턴스(기본)

가장 먼저 익혀야 할 패턴입니다.

1. 라우터는 1개 (`Host(api.localhost)`)
2. 서비스는 N개 인스턴스
3. Traefik이 인스턴스 목록을 로드밸런싱

File provider 예시:

```yaml
http:
  routers:
    api-router:
      rule: "Host(`api.localhost`)"
      entryPoints: ["web"]
      service: api-svc
      middlewares: ["default-chain"]

  services:
    api-svc:
      loadBalancer:
        servers:
          - url: "http://api-1:80"
          - url: "http://api-2:80"
          - url: "http://api-3:80"
```

주의:
1. `servers.url` 목록은 실제 백엔드 컨테이너 이름/포트와 정확히 일치해야 합니다.
2. 인스턴스 수를 바꾸면 `dynamic.yml` 서버 목록도 함께 갱신해야 합니다.

실행:

```bash
docker compose -f examples/docker-compose.yml up -d
```

검증:

```bash
for i in {1..10}; do
  curl -s -H 'Host: api.localhost' http://localhost | grep -i hostname
done
```

`hostname` 값이 여러 값으로 섞여 나오면 분산이 정상입니다.

## 패턴 B: 서비스별 격리(서브도메인 단위 경계)

다중 서버 운영에서 가장 중요한 것은 "확장"보다 "격리"입니다.

권장 경계:
1. `app.localhost` 라우트는 app 풀만 참조
2. `api.localhost` 라우트는 api 풀만 참조
3. `admin.localhost` 라우트는 admin 풀만 참조

피해야 할 패턴:
1. 편의상 여러 라우터가 같은 백엔드 풀을 공유
2. 장애 시 여러 서브도메인이 동시에 영향 받음

운영 기준:
1. 라우터 이름, 서비스 이름, 도메인 이름을 1:1로 맞춘다.
2. 로그/알람도 서비스 경계 기준으로 분리한다.

## 패턴 C: 헬스체크와 자동 제외

다중 인스턴스는 "죽은 인스턴스를 빨리 제외"해야 의미가 있습니다.

Traefik HTTP 서비스 헬스체크 예시:

```yaml
http:
  services:
    api-svc:
      loadBalancer:
        servers:
          - url: "http://api-1:80"
          - url: "http://api-2:80"
          - url: "http://api-3:80"
        healthCheck:
          path: "/health"
          interval: "10s"
          timeout: "2s"
```

적용 포인트:
1. 백엔드에 경량 `health` 엔드포인트를 별도로 둔다.
2. 비즈니스 로직 의존이 큰 무거운 체크는 피한다.
3. 헬스체크 실패 시 자동 제외되는지 대시보드/로그로 검증한다.

## 패턴 D: 세션 고정(sticky)이 필요한 경우

기본은 비고정(round-robin)에 가깝게 운영하는 것이 단순합니다.  
다만 레거시 앱처럼 세션 고정이 필요하면 서비스 단위로만 제한적으로 적용합니다.

예:

```yaml
http:
  services:
    app-svc:
      loadBalancer:
        sticky:
          cookie: {}
```

주의:
1. sticky 적용은 트래픽 분산 효율을 낮출 수 있다.
2. 가능한 앱 자체를 stateless로 개선하는 것이 장기적으로 유리하다.

## 실습: 다중 서버 프록시 구성 절차

## 1단계: compose에 백엔드 인스턴스 추가

`api-1`, `api-2`, `api-3` 컨테이너를 compose에 추가하고 실행합니다.

## 2단계: dynamic.yml에 서버 목록 선언

`api-svc.loadBalancer.servers`에 세 인스턴스 URL을 모두 선언합니다.

## 3단계: 분산 확인

```bash
for i in {1..10}; do
  curl -s -H 'Host: api.localhost' http://localhost | grep -E 'Hostname|IP'
done
```

## 4단계: 장애 주입 테스트

1. API 인스턴스 1개를 임의 중지
2. 같은 요청을 반복 호출
3. 성공률/응답 지연/오류 패턴 확인

예시:

```bash
docker stop api-1
for i in {1..10}; do
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: api.localhost' http://localhost
done
```

정상 기준:
1. 일부 인스턴스 중지 후에도 대부분 200 유지
2. 라우터/서비스 자체는 유지되고 대상 인스턴스만 줄어듦

## 관측과 디버깅 포인트

1. Dashboard
- 라우터 1개 + 서비스 1개 + 서버 N개 구조인지 확인

2. Access log
- 요청이 어느 백엔드로 갔는지 패턴 확인

3. Traefik logs
- 서버 추가/제거 이벤트, 헬스체크 실패 이벤트 확인

명령:

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

## 자주 발생하는 실수

1. 서버 목록 누락/오탈자
- 증상: 일부 인스턴스로만 트래픽 고정 또는 502
- 조치: `services.<name>.loadBalancer.servers` 전체 URL 재확인

2. 도메인 분리 없이 path만으로 모든 서비스를 한 덩어리로 관리
- 증상: 장애 영향 범위가 커짐
- 조치: 최소한 외부 경계는 Host 단위로 먼저 분리

3. 헬스체크 없는 다중 인스턴스 운영
- 증상: 죽은 인스턴스로 트래픽 유입
- 조치: `/health` 기반 체크를 기본값으로 채택

4. 검증 없이 서버 수만 증가
- 증상: 분산이 제대로 안 되는데도 운영 투입
- 조치: 반복 `curl`과 Dashboard로 분산/제외 동작 확인

## 운영 체크리스트

1. 도메인-라우터-서비스 네이밍 규칙이 일관적인가
2. 서비스별 최소 인스턴스 수가 문서화되어 있는가
3. 헬스체크 엔드포인트가 안정적이고 가벼운가
4. 장애 주입 테스트를 배포 전 수행했는가
5. 대시보드 공개 범위를 내부 네트워크로 제한했는가

## 요약

1. 다중 서버 프록시의 핵심은 "분산"보다 "격리 + 자동 제외"다.
2. Host 기반 경계를 유지한 채 인스턴스 수를 확장해야 운영이 단순해진다.
3. 헬스체크/로그/대시보드로 분산 동작을 반드시 검증해야 한다.
4. 다음 장에서는 같은 원리를 도메인 대신 `Path` 경계로 옮겨 API 게이트웨이 라우팅을 구성한다.

## 다음 챕터

- [06. Path 게이트웨이 라우팅](./06-path-based-gateway-routing.md)
