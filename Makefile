.PHONY: compose-up compose-down compose-logs compose-restart

compose-up:
	@docker compose -f examples/docker-compose.yml up -d

compose-down:
	@docker compose -f examples/docker-compose.yml down

compose-logs:
	@docker compose -f examples/docker-compose.yml logs -f

compose-restart:
	@docker compose -f examples/docker-compose.yml down && docker compose -f examples/docker-compose.yml up -d
