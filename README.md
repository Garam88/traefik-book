# Traefik 프록시/게이트웨이 핸드북

- 이 저장소는 오픈소스 Traefik으로 프록시 서버와 API 게이트웨이를 실무 수준으로 구성하기 위한 가이드북입니다.
- 이 프로젝트는 GPT-5.3-Codex를 활용하여 제작되었습니다.

## 이 책을 보면 할 수 있는 일

1. 서브도메인 기준으로 여러 백엔드 서버로 요청을 분기하는 리버스 프록시를 구성한다.
2. Path 기준으로 여러 서비스를 라우팅하는 API 게이트웨이를 구성한다.
3. 특정 요청을 다른 프록시(상위 프록시)로 그대로 전달하는 프록시 체인을 구성한다.

## 디렉터리 구조

- docs/: 책 원고 작업 공간 (docs/chapters 중심)
- examples/: 실행 가능한 실습 환경 (traefik-lab)
- Makefile: 자주 쓰는 실행 명령 모음

## 전체 챕터 목차

- [00. 가이드 목표와 완성 시나리오](docs/chapters/00-guide-goals-and-outcomes.md)
- [01. Traefik 핵심 구조: 프록시와 게이트웨이 관점](docs/chapters/01-traefik-core-for-proxy-and-gateway.md)
- [02. 실습 환경 준비: 도메인/네트워크/Docker](docs/chapters/02-lab-setup-and-network-basics.md)
- [03. 설정의 기초: Static, Dynamic, Providers](docs/chapters/03-static-dynamic-config-and-providers.md)
- [04. 서브도메인 라우팅 1: Host 규칙으로 분기](docs/chapters/04-subdomain-routing-with-host-rules.md)
- [05. 서브도메인 라우팅 2: 다중 서버 프록시 패턴](docs/chapters/05-multi-service-proxy-patterns.md)
- [06. Path 게이트웨이 라우팅](docs/chapters/06-path-based-gateway-routing.md)
- [07. 게이트웨이 미들웨어: StripPrefix, Rewrite, 정책 적용](docs/chapters/07-gateway-middlewares-for-path-services.md)
- [08. 특정 요청을 다른 프록시로 전달하기 (Proxy Chaining)](docs/chapters/08-forwarding-to-another-proxy.md)
- [09. 엣지 보안 필수: 인증, 헤더, 속도 제한](docs/chapters/09-security-basics-for-edge-routing.md)
- [10. TLS/HTTPS 및 인증서 자동화](docs/chapters/10-tls-and-certificates-with-acme.md)
- [11. 관측성/디버깅: 로그, 메트릭, 대시보드](docs/chapters/11-observability-and-debugging.md)
- [12. 운영 배포: 아키텍처, 고가용성, 변경 전략](docs/chapters/12-production-architecture-and-deployment.md)
- [13. 실전 레시피 A: 멀티 서브도메인 프록시](docs/chapters/13-recipe-subdomain-multi-server-proxy.md)
- [14. 실전 레시피 B: Path 게이트웨이 + 프록시 체이닝](docs/chapters/14-recipe-path-gateway-and-proxy-chaining.md)
- [15. 부록: 규칙 치트시트와 설정 템플릿](docs/chapters/15-appendix-cheatsheets-and-templates.md)

## 예시 코드 빠른 시작

```bash
make compose-up
```

테스트:

```bash
curl -H 'Host: whoami.localhost' http://localhost
```

중지:

```bash
make compose-down
```

## 라이선스

- 문서: CC BY-NC-SA 4.0
- 예제 코드: MIT
