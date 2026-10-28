SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: help local-up local-down local-logs screenshots check-screenshots

help:
	@printf '%s\n' \
	  'local-up/down/logs    Operate the development Compose project' \
	  'screenshots           Regenerate README screenshots with isolated demo data' \
	  'check-screenshots     Verify README screenshots are up to date' \
	  'deploy-init/upload   Prepare and distribute the selected server recipe' \
	  'deploy-preflight     Validate Docker, Compose and configured paths' \
	  'deploy-build         Build/export an image with configurable local Docker/platform' \
	  'deploy-install       Install a new project with migrations and HTTP verification' \
	  'deploy-update        Update an existing project with backup and recovery guards' \
	  'deploy-release       Deploy the verified digest of a published main commit' \
	  'deploy-media-up/status/logs/stop  Operate optional Sonarr, Radarr and Prowlarr' \
	  'deploy-backup        Save a validated private PostgreSQL backup' \
	  'deploy-restore       Restore BACKUP_FILE with explicit confirmation' \
	  'deploy-status/logs/console/psql/stop  Operate locally or over SSH using DEPLOY_CONFIG'

local-up:
	@mkdir -p media
	@docker compose up --build

local-down:
	@docker compose down

local-logs:
	@docker compose logs --tail 100 --follow app db

screenshots:
	@bash scripts/capture_readme.sh

check-screenshots:
	@bash scripts/capture_readme.sh --check

DEPLOY_CONFIG ?= .env.deploy
-include $(DEPLOY_CONFIG)
DEPLOY_TRANSPORT ?= local
DEPLOY_DIR ?= /srv/bolognesa
DEPLOY_SOURCE_DIR ?= $(CURDIR)/deploy/compose
DOCKER_BIN ?= docker
DEPLOY_COMPOSE_FILES ?= compose.yaml
DEPLOY_HEALTH_URL ?= http://127.0.0.1:4000/
DEPLOY_SCRIPT := deploy/compose/scripts/deploy.sh
export DEPLOY_CONFIG DEPLOY_TRANSPORT DEPLOY_HOST DEPLOY_DIR DEPLOY_SOURCE_DIR DOCKER_BIN DEPLOY_COMPOSE_FILES DEPLOY_HEALTH_URL DEPLOY_BACKUP_DIR DEPLOY_IMAGE_NAME DEPLOY_IMAGE_TAR DEPLOY_BUILD_PLATFORM
export BUILD_DOCKER_BIN IMAGE_REF BACKUP_FILE DEPLOY_MIN_FREE_KIB
export ALLOW_DATABASE_CONFIG_CHANGE EXPECTED_DATABASE_SOURCE IMAGE_REPOSITORY DEPLOY_WORKFLOW DEPLOY_ARTIFACT DEPLOY_RUN_ID COMMIT_SHA

.PHONY: deploy-preflight deploy-init deploy-build deploy-upload deploy-install deploy-update deploy-release deploy-backup deploy-restore deploy-status deploy-logs deploy-console deploy-psql deploy-stop
.NOTPARALLEL: deploy-install deploy-update deploy-release deploy-media-up

deploy-install: deploy-upload deploy-preflight
	@bash $(DEPLOY_SCRIPT) install "$${IMAGE_REF:-}"

deploy-update: deploy-upload deploy-preflight
	@bash $(DEPLOY_SCRIPT) update "$${IMAGE_REF:-}"

deploy-release:
	@bash deploy/compose/scripts/release.sh

deploy-restore:
	@test -n "$${BACKUP_FILE:-}" || { echo 'Set BACKUP_FILE to an existing backup on the server' >&2; exit 2; }
	@bash $(DEPLOY_SCRIPT) restore "$${BACKUP_FILE:-}"

deploy-media-up: deploy-upload deploy-preflight
	@bash $(DEPLOY_SCRIPT) media-up

.PHONY: deploy-media-up deploy-media-status deploy-media-logs deploy-media-stop
deploy-preflight deploy-init deploy-build deploy-upload deploy-backup deploy-status deploy-logs deploy-console deploy-psql deploy-stop deploy-media-status deploy-media-logs deploy-media-stop:
	@bash $(DEPLOY_SCRIPT) $(patsubst deploy-%,%,$@)
