# 12. 운영 배포: 아키텍처, 고가용성, 변경 전략

이 장은 "동작하는 설정"을 "운영 가능한 시스템"으로 바꾸는 단계입니다.  
핵심은 단순 배포가 아니라, 장애 시에도 서비스를 유지하고 빠르게 되돌릴 수 있는 구조를 갖추는 것입니다.

## 이 장을 끝내면 할 수 있는 일

1. Traefik 운영 아키텍처(단일/이중화)를 요구사항에 맞게 선택한다.
2. 설정 변경을 무중단에 가깝게 배포하고 실패 시 즉시 롤백한다.
3. 고가용성, 보안, 관측, 변경 관리를 하나의 운영 런북(runbook)으로 묶는다.

## 반드시 알아야 할 핵심

- 롤백 가능한 배포 단위를 먼저 정의하지 않으면, 고가용성 설계도 실제 장애에서 무력화된다.

## 운영 아키텍처 기준선

가장 먼저 결정할 항목:
1. 트래픽 규모와 허용 다운타임
2. 인증서 발급/저장 방식
3. 배포 자동화 수준(CI/CD)

## 패턴 A: 단일 노드(초기 단계)

구성:
1. Traefik 1대
2. 백엔드 N개
3. 단일 ACME 저장소

장점:
1. 단순, 비용 낮음

한계:
1. Traefik 자체가 SPOF(단일 장애점)
2. 유지보수/재시작 시 가용성 저하 가능

## 패턴 B: 이중화(운영 기본)

구성:
1. L4/L7 로드밸런서 앞단
2. Traefik 2대 이상(무상태)
3. 백엔드 다중 인스턴스
4. 공통 관측/알림

장점:
1. 단일 노드 장애 흡수
2. 무중단 배포 가능성 증가

주의:
1. 인증서 저장/발급 정책을 노드 간 일관되게 관리해야 함
2. 설정 배포 순서가 어긋나면 노드별 동작 차이가 발생

## 배포 단위 전략 (Static vs Dynamic)

03장에서 분리한 원칙을 운영 배포 단위로 확장합니다.

1. Static 변경
- 예: entrypoint, provider, ACME resolver
- 특성: 재시작 영향 큼
- 배포 전략: 카나리 노드 -> 검증 -> 점진 롤링

2. Dynamic 변경
- 예: router/service/middleware
- 특성: 즉시 반영 가능
- 배포 전략: small batch 변경 + 즉시 검증 + 빠른 revert

핵심:
1. 변경 요청서에 "Static/Dynamic 분류"를 명시
2. 분류에 따라 배포 창구와 승인 수준을 다르게 운영

## 고가용성 설계 체크포인트

## 1) Traefik 인스턴스 이중화

1. 최소 2개 인스턴스
2. anti-affinity(가능한 경우)로 장애 도메인 분리
3. readiness/liveness 체크 설정

## 2) 백엔드 풀 가용성

1. 서비스별 최소 인스턴스 수 정의
2. healthcheck endpoint 표준화(`/healthz`)
3. rate limit/timeouts를 서비스 특성별로 튜닝

## 3) 인증서/비밀 관리

1. `acme.json` 등 민감 파일 권한 통제
2. 백업/복구 절차 문서화
3. 다중 인스턴스 시 인증서 동기화 전략 확정

## 4) 운영 관측

1. access log 중앙 수집
2. 4xx/5xx/latency 임계치 알림
3. 인증서 만료/갱신 실패 알림

## 변경 전략: 안전한 롤아웃 절차

권장 표준 절차:

1. 변경 준비
- 변경 diff 리뷰
- 영향 라우트 목록 작성
- 롤백 커밋/태그 미리 준비

2. 사전 검증
- `docker compose ... config` 또는 배포 플랫폼 lint
- 스테이징 smoke test

3. 점진 배포
- 카나리 노드 1대 적용
- 주요 경로(`api/auth/admin/legacy`) 즉시 검증
- 이상 없으면 전체 노드 롤링

4. 배포 후 확인
- 에러율/지연/트래픽 분포 모니터링
- 대시보드의 `rawdata`로 설정 일치 확인

실행 예시(로컬/단순 운영):

```bash
docker compose -f examples/docker-compose.yml config
docker compose -f examples/docker-compose.yml up -d
docker compose -f examples/docker-compose.yml logs -f traefik
```

## 롤백 전략 (필수)

롤백은 "문서"가 아니라 "명령 가능 상태"여야 합니다.

## 최소 롤백 준비물

1. 마지막 안정 설정 커밋/태그
2. 되돌리기 명령 템플릿
3. 복구 검증 URL 목록

예시:

```bash
# 1) 이전 안정 버전으로 되돌림
git checkout <stable-tag-or-commit> -- examples/docker-compose.yml examples/traefik-lab/dynamic/dynamic.yml

# 2) 재배포
docker compose -f examples/docker-compose.yml up -d

# 3) 핵심 경로 검증
curl -I -H 'Host: gateway.localhost' http://localhost/api/health
curl -I -H 'Host: gateway.localhost' http://localhost/auth/health
```

롤백 트리거 예시:
1. 5xx 비율 급증
2. 인증 실패 급증(401/403)
3. 체이닝 경로 루프/타임아웃 반복

## 장애 시 의사결정 규칙

1. 1차 목표는 기능 완성이 아니라 서비스 복구
2. 원인 분석은 복구 이후 진행
3. 롤백 임계치(예: 5xx 2% 초과 5분)를 사전에 정의

## 운영 런북(runbook) 템플릿

운영자가 바로 쓰는 최소 런북(runbook):

1. 증상
- 어떤 경로/도메인에서 어떤 상태코드가 증가했는가

2. 영향 범위
- Public only / Internal only / Legacy chain 포함 여부

3. 즉시 조치
- 카나리 중단, 이전 설정 롤백, 트래픽 우회

4. 검증
- 핵심 URL smoke test
- access log와 에러율 정상화 확인

5. 사후 조치
- 원인 분석(RCA)
- 재발 방지 체크리스트 업데이트

## 배포 실패 패턴과 대응

1. 노드별 설정 불일치
- 원인: 부분 배포/캐시/동기화 누락
- 대응: 배포 완료 후 모든 노드 `rawdata` 비교

2. 동적 설정 오탈자
- 원인: 라우터/미들웨어 이름 mismatch
- 대응: 배포 전 자동 lint + 배포 직후 smoke test

3. 인증서 저장소 문제
- 원인: 권한/볼륨 설정 오류
- 대응: 파일 권한 점검, 만료 알림, 백업 복구 테스트

4. 롤백 실패
- 원인: 롤백 아티팩트 미준비
- 대응: 릴리즈마다 안정 태그/복구 명령 자동 생성

## 운영 체크리스트

1. Traefik 인스턴스가 최소 2대 이상인가
2. Static/Dynamic 변경 분류가 배포 프로세스에 포함되는가
3. 카나리 -> 롤링 -> 검증 절차가 문서화되어 있는가
4. 롤백 명령과 안정 버전 포인터가 항상 준비되는가
5. 인증서/로그/알림 체계가 운영 기준을 만족하는가

## 요약

1. 운영 배포의 핵심은 기능 추가가 아니라 "지속 가능한 변경"이다.
2. 고가용성은 인스턴스 수만 늘리는 것이 아니라 배포/롤백 체계까지 포함한다.
3. 롤백 가능한 배포 단위를 먼저 정의하면 장애 대응 시간이 크게 줄어든다.
4. 다음 장에서는 이 운영 기준을 바탕으로 실제 요구사항을 받아 멀티 서브도메인 프록시를 완성한다.

## 다음 챕터

- [13. 실전 레시피 A: 멀티 서브도메인 프록시](./13-recipe-subdomain-multi-server-proxy.md)
