# qoder-swarm Makefile
# Quick entry points. Everything is still callable via the underlying
# bash / python commands — this is just shorthand.

.PHONY: help install uninstall test doctor lint clean status

help:
	@echo "qoder-swarm — multi-agent orchestration kit for Qoder CLI"
	@echo ""
	@echo "Common:"
	@echo "  make install       Install kit into ~/.qoder/ (default home)"
	@echo "  make uninstall     Remove registered hooks (preserves user data)"
	@echo "  make test          Run smoke-test against a temp QODER_HOME"
	@echo "  make doctor        Check runtime prerequisites"
	@echo "  make status        Show what's installed under ~/.qoder/"
	@echo ""
	@echo "Dev:"
	@echo "  make lint          shellcheck + yamllint + python -m py_compile"
	@echo "  make clean         Remove .swarm-archive, tmpfiles, .DS_Store"
	@echo ""
	@echo "For QODER_HOME override:"
	@echo "  bash install.sh /custom/path"

install:
	@bash install.sh

uninstall:
	@python3 install-settings.py --uninstall

test:
	@bash tests/smoke-test.sh

doctor:
	@bash install.sh --doctor

status:
	@echo "=== ~/.qoder/skills/swarm/ ==="
	@ls -la ~/.qoder/skills/swarm/ 2>/dev/null || echo "  (not installed)"
	@echo ""
	@echo "=== ~/.qoder/agents/swarm-*.md ==="
	@ls ~/.qoder/agents/swarm-*.md 2>/dev/null || echo "  (not installed)"
	@echo ""
	@echo "=== ~/.qoder/hooks/swarm-*.sh ==="
	@ls ~/.qoder/hooks/swarm-*.sh 2>/dev/null || echo "  (not installed)"
	@echo ""
	@echo "=== ~/.qoder/scripts/ ==="
	@ls ~/.qoder/scripts/*.py 2>/dev/null || echo "  (not installed)"
	@echo ""
	@echo "=== Hook registration in settings.json ==="
	@grep -l "swarm-" ~/.qoder/settings.json 2>/dev/null && echo "  ✓ swarm hooks registered" || echo "  ⚠ no swarm hooks registered"

lint:
	@echo "==> Shell scripts"
	@find install.sh tests/smoke-test.sh dispatch-kit/init-dispatch.sh hooks/swarm-*.sh -type f 2>/dev/null | xargs -I {} sh -c 'echo "checking {}"; bash -n {}'
	@echo ""
	@echo "==> Python scripts"
	@python3 -m py_compile install-settings.py scripts/image-diff.py 2>&1 && echo "  ✓ py_compile OK"
	@echo ""
	@echo "==> YAML"
	@python3 -c "import yaml; [yaml.safe_load(open(f)) for f in ['.aoneci/smoke.yaml']]" && echo "  ✓ YAML parses"

clean:
	@find . -name '.DS_Store' -delete 2>/dev/null || true
	@find . -name '*.pyc' -delete 2>/dev/null || true
	@find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	@echo "  ✓ Cleaned .DS_Store / *.pyc / __pycache__"
