# 11. 관측성/디버깅: 로그, 메트릭, 대시보드

10장에서 TLS까지 구성했으면, 이제 장애가 났을 때 "어디서 깨졌는지"를 빠르게 찾을 수 있어야 합니다.  
이 장은 Traefik 디버깅을 감이 아니라 절차로 수행하는 방법을 다룹니다.

## 이 장을 끝내면 할 수 있는 일

1. 요청 실패를 `라우터 매칭`, `미들웨어`, `업스트림`, `TLS` 중 어디 문제인지 분류한다.
2. 대시보드/API/`rawdata`/access log를 조합해 원인을 단계적으로 좁힌다.
3. 재현 가능한 디버깅 루틴을 운영 런북(runbook)으로 정리한다.

## 반드시 알아야 할 핵심

- `access log`의 라우터/서비스 매핑과 `rawdata`를 함께 보면 원인 분리가 빨라진다.

## 관측 신호 4종 세트

Traefik 디버깅은 아래 4개를 기본 세트로 봅니다.

1. Dashboard UI
- 현재 라우터/서비스/미들웨어 상태를 빠르게 확인

2. `rawdata` API
- 런타임에 실제 로드된 설정(JSON) 확인

3. Access log
- 요청 단위 결과(상태 코드/경로/처리 시간) 확인

4. Traefik application log
- provider reload, ACME, 라우팅/연결 오류 이벤트 확인

## 1) Dashboard로 1차 분류

로컬 실습:
- `http://localhost:8080/dashboard/`

먼저 볼 것:
1. 문제가 된 라우터가 실제로 존재하는가
2. 라우터 규칙(`Host`, `PathPrefix`)이 의도와 일치하는가
3. 연결된 서비스/미들웨어가 맞는가

초기 분류:
1. 라우터 자체가 없음 -> provider 로딩/네이밍 문제
2. 라우터는 있음, 404 -> rule 매칭/priority 문제
3. 라우터는 있음, 502/504 -> 업스트림/네트워크/timeout 문제

## 2) `rawdata`로 런타임 설정 사실 확인

대시보드가 보여주는 내용이 축약될 수 있으므로 `rawdata`로 최종 확인합니다.

```bash
curl -s http://localhost:8080/api/rawdata | jq .
```

확인 포인트:
1. router 이름과 rule 문자열
2. router -> service 연결
3. middleware 체인 순서
4. tls/certresolver 연결

주의:
1. 설정 파일에 있는 내용이 아니라 "실제로 로드된 내용"이 기준입니다.

## 3) Access log로 요청 단위 추적

현재 실습 구성은 `--accesslog=true`가 이미 활성화되어 있습니다.

```bash
docker compose -f examples/docker-compose.yml logs -f traefik
```

요청 추적 시 확인:
1. 어떤 path/host 요청이 들어왔는지
2. 최종 상태 코드(2xx/4xx/5xx)
3. 응답 시간(지연 급증 여부)
4. 동일 요청의 반복 실패 패턴

운영 팁:
1. 문제 요청을 재현할 때 `X-Request-Id` 헤더를 붙여 상관관계를 맞추면 추적이 쉬움

```bash
curl -H 'Host: gateway.localhost' -H 'X-Request-Id: debug-001' http://localhost/api/health
```

## 4) 애플리케이션 로그로 이벤트 확인

Traefik 로그는 "구성 변경 이벤트 + 런타임 오류"를 보여줍니다.

대표 확인 항목:
1. provider reload 성공/실패
2. middleware not found
3. service unreachable
4. ACME/TLS 발급 오류

로그 수준:
1. 평시: `INFO`
2. 장애 분석: 일시적으로 `DEBUG` 올려서 상세 추적

주의:
1. `DEBUG`는 로그량이 크므로 장애 조사 후 원복

## 디버깅 표준 절차 (런북, runbook)

문제 발생 시 아래 순서로 고정합니다.

1. 증상 분류
- 404 / 401 / 429 / 502 / 504 / TLS 오류

2. 대시보드 확인
- 라우터 존재/규칙/서비스 연결 확인

3. `rawdata` 확인
- 런타임 구성 오탈자/누락 확인

4. access log 확인
- 요청 단위 상태 코드/지연/패턴 확인

5. upstream 점검
- 백엔드 health/포트/네트워크 확인

6. 수정 후 재검증
- 동일 `curl` 시나리오로 회귀 테스트

## 상태 코드별 빠른 원인 지도

1. 404
- 주 원인: 라우터 미매칭, 우선순위 충돌

2. 401/403
- 주 원인: 인증 미들웨어 정책/헤더 누락

3. 429
- 주 원인: rate limit 과도 설정

4. 502
- 주 원인: 업스트림 연결 실패(주소/포트/네트워크)

5. 504
- 주 원인: 업스트림 지연/timeout 설정 미흡

6. TLS 핸드셰이크 오류
- 주 원인: 인증서/도메인 불일치, resolver 실패

## 실습: 실패 시나리오 재현과 복구

## 시나리오 A: 라우터 오탈자(404)

1. 라우터 rule의 Host를 일부러 틀리게 변경
2. 요청 시 404 확인
3. Dashboard와 `rawdata`에서 rule 불일치 확인
4. 수정 후 200 복구 확인

## 시나리오 B: 미들웨어 참조 오류(500/502 계열)

1. 존재하지 않는 미들웨어 참조
2. 로그에서 `middleware not found` 확인
3. 미들웨어 이름 수정 후 정상화

## 시나리오 C: 업스트림 장애(502)

1. 대상 서비스 컨테이너 중지
2. 같은 요청 반복
3. 502 패턴과 로그 메시지 확인
4. 컨테이너 복구 후 200 확인

## 관측성 확장 (운영 권장)

현재 챕터의 기본은 로그/대시보드지만, 운영에서는 메트릭/트레이싱도 함께 사용합니다.

1. Metrics(Prometheus)
- 요청량, 지연, 상태코드 분포, 라우터별 추이

2. Tracing(OpenTelemetry/Jaeger 등)
- 게이트웨이 -> 업스트림 경로 지연 구간 분석

원칙:
1. 장애 대응 1차는 logs와 Dashboard
2. 성능/추세 분석은 metrics/tracing

## 운영 체크리스트

1. 표준 디버깅 절차(런북, runbook)가 문서화되어 있는가
2. access log가 보존/검색 가능한가
3. `rawdata` 접근이 내부망으로 제한되어 있는가
4. 상태코드 급증(404/5xx/429) 알림이 구성되어 있는가
5. 장애 후 재현 시나리오가 회귀 테스트로 남는가

## 요약

1. 관측성의 목표는 "빨리 많이 보는 것"이 아니라 "원인 범위를 빠르게 줄이는 것"이다.
2. 대시보드 -> `rawdata` -> `access log` -> upstream 점검 순서가 가장 안정적이다.
3. 상태 코드별 원인 지도를 팀 공통 규칙으로 두면 대응 시간이 크게 단축된다.
4. 다음 장에서는 이 관측 루틴을 운영 배포/고가용성/변경 전략과 연결한다.

## 다음 챕터

- [12. 운영 배포: 아키텍처, 고가용성, 변경 전략](./12-production-architecture-and-deployment.md)
