SH ?= $(shell command -v bash)
PYTHON ?= python3
SHELLCHECK ?= shellcheck

OUR_SH = install.sh scripts/04n-lowspec-niri.sh scripts/lib/common.sh \
         live/install.sh live/lib/common.sh \
         live/steps/10-partition.sh live/steps/20-bootstrap.sh \
         live/steps/30-chroot-base.sh live/steps/40-deploy.sh live/steps/50-modules.sh \
         tests/e2e/merge.sh vm/run.sh vm/live-autoinstall.sh vm/paste.sh live/enable-ssh.sh live/remote-install.sh

.PHONY: help test lint e2e check live-dry-run vm clean

help:
	@echo "make test          单元测试（tools/niri_patch.py）"
	@echo "make lint          bash -n + py_compile + shellcheck(-S error)"
	@echo "make e2e           在假 HOME 上跑真实 04n：合并/幂等/undo/契约检查"
	@echo "make check         lint + test + e2e（CI 用）"
	@echo "make live-dry-run  打印 live 安装器将执行的命令"
	@echo "make vm            启动 QEMU 验证环境（需要 Arch ISO）"

test:
	$(PYTHON) -m unittest discover -s tests -v

lint:
	@for f in $(OUR_SH); do bash -n "$$f" || exit 1; done
	$(PYTHON) -m py_compile tools/niri_patch.py vm/paste.py
	@if command -v $(SHELLCHECK) >/dev/null 2>&1; then \
		$(SHELLCHECK) -S error $(OUR_SH); \
	else echo "shellcheck 未安装，跳过"; fi
	@echo "lint: ok"

e2e:
	bash tests/e2e/merge.sh

check: lint test e2e

live-dry-run:
	DISK=/dev/vda bash live/install.sh --dry-run --yes --config live/install.env.example

vm:
	bash vm/run.sh

clean:
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
	rm -rf vm/arch-test.qcow2 vm/edk2-vars.fd vm/serial.log
