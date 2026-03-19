PREFIX ?= /usr/local

.PHONY: install uninstall link test help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install wf to PREFIX/bin (default /usr/local)
	@mkdir -p $(PREFIX)/bin
	@cp bin/wf $(PREFIX)/bin/wf
	@chmod +x $(PREFIX)/bin/wf
	@echo "Installed wf to $(PREFIX)/bin/wf"
	@echo ""
	@echo "Also add to your .zshrc for shell integration:"
	@echo "  source $(shell pwd)/work-forest.plugin.zsh"

uninstall: ## Remove wf from PREFIX/bin
	@rm -f $(PREFIX)/bin/wf
	@echo "Removed $(PREFIX)/bin/wf"

link: ## Symlink wf to PREFIX/bin (for development)
	@mkdir -p $(PREFIX)/bin
	@ln -sf $(shell pwd)/bin/wf $(PREFIX)/bin/wf
	@chmod +x bin/wf
	@echo "Linked $(PREFIX)/bin/wf -> $(shell pwd)/bin/wf"

test: ## Run tests
	@echo "Running tests..."
	@zsh tests/test_toml.zsh
	@zsh tests/test_core.zsh
	@zsh tests/test_git.zsh
	@zsh tests/test_forest.zsh
	@zsh tests/test_agent.zsh
	@zsh tests/test_integration.zsh
	@echo ""
	@echo "═══════════════════════════"
	@echo "  All test suites passed!"
	@echo "═══════════════════════════"
