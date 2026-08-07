SITE_REPO := git@github.com:HealthSamurai/health-samurai-io-bun.git
SITE_DIR  := $(abspath ../health-samurai-io-bun)

.PHONY: preview
preview:
	@test "$(notdir $(CURDIR))" = "aidbox-docs" || echo "warning: docs dev mode looks up this checkout by the name 'aidbox-docs', but it is named '$(notdir $(CURDIR))'"
	@test -d $(SITE_DIR) || { \
		echo "Docs site repo not found at $(SITE_DIR)"; \
		echo "Clone it first:"; \
		echo "  git clone $(SITE_REPO) $(SITE_DIR)"; \
		exit 1; }
	@test -d $(SITE_DIR)/node_modules || (cd $(SITE_DIR) && bun install)
	@echo "Docs preview: http://localhost:4444/docs/aidbox"
	cd $(SITE_DIR) && DOCS_DEV_MODE=true DOCS_REPOS_PATH=$(abspath ..) bun dev:fg
