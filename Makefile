SHORIN ?=
PYTHON ?= python3

.PHONY: help test lint deploy check clean

help:
	@echo "make test                 跑 tools/niri_patch.py 的单元测试"
	@echo "make lint                 bash -n + python 语法检查"
	@echo "make deploy SHORIN=路径   把安装脚本/overlay/工具部署进 shorin-arch-setup"
	@echo "make check                一次跑完 lint + test"

test:
	$(PYTHON) -m unittest discover -s tests -v

lint:
	bash -n install/04n-lowspec-niri.sh
	$(PYTHON) -m py_compile tools/niri_patch.py
	@if command -v shellcheck >/dev/null; then shellcheck -S error install/04n-lowspec-niri.sh; \
	 else echo "shellcheck 未安装，跳过"; fi
	@echo "lint: ok"

check: lint test

deploy:
	@test -n "$(SHORIN)" || { echo "usage: make deploy SHORIN=/path/to/shorin-arch-setup"; exit 2; }
	@test -d "$(SHORIN)/scripts" || { echo "$(SHORIN)/scripts 不存在"; exit 2; }
	install -Dm755 install/04n-lowspec-niri.sh     "$(SHORIN)/scripts/04n-lowspec-niri.sh"
	install -Dm755 tools/niri_patch.py             "$(SHORIN)/resources/niri-merge-tools/niri_patch.py"
	rsync -a --delete overlay/                     "$(SHORIN)/resources/niri-merge-overlay/"
	@test -d "$(SHORIN)/low-spec-dotfiles" || \
		echo "提醒：$(SHORIN)/low-spec-dotfiles 还没克隆，执行 git clone --depth=1 https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles.git $(SHORIN)/low-spec-dotfiles"
	@echo "deploy: ok -> $(SHORIN)/scripts/04n-lowspec-niri.sh"

clean:
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
