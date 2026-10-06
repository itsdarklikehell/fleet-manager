.PHONY: all test lint install clean docker-build docker-run help

# Default target
all: test lint

# Test all scripts
test:
	@echo "=== Running test suite ==="
	bash scripts/test-suite.sh
	@echo "=== Running E2E tests ==="
	bash tests/test-e2e.sh
	@echo "=== Running integration tests ==="
	bash tests/test-integration.sh

# Lint all scripts
lint:
	@echo "=== Checking bash syntax ==="
	@for script in scripts/*.sh lib/*.sh; do \
		[ -f "$$script" ] && bash -n "$$script" || true; \
	done
	@echo "=== Running shellcheck (warnings only) ==="
	@for script in scripts/*.sh lib/*.sh; do \
		[ -f "$$script" ] && shellcheck -S warning "$$script" 2>&1 | grep -v "^$$" || true; \
	done
	@echo "=== Lint complete ==="

# Install fleet-manager
install:
	@echo "=== Installing fleet-manager ==="
	@mkdir -p $(HOME)/.local/bin
	@cp -r scripts lib $(HOME)/.local/bin/
	@cp github_fleet_manager.sh $(HOME)/.local/bin/
	@echo "Installed to $(HOME)/.local/bin/"

# Clean up
clean:
	@echo "=== Cleaning up ==="
	@rm -rf __pycache__ .pytest_cache
	@find . -name "*.pyc" -delete
	@find . -name "*.log" -delete

# Docker build
docker-build:
	@echo "=== Building Docker image ==="
	docker build -t fleet-manager:latest .

# Docker run
docker-run:
	@echo "=== Running Docker container ==="
	docker run --rm -it fleet-manager:latest

# Help
help:
	@echo "Available targets:"
	@echo "  test         - Run all tests"
	@echo "  lint         - Run shellcheck and bash syntax check"
	@echo "  install      - Install fleet-manager to ~/.local/bin"
	@echo "  clean        - Clean up temporary files"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run Docker container"
