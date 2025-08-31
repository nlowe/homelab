.PHONY: diff
diff:
	tk diff environments/default


.restore.stamp: jsonnetfile.json jsonnetfile.lock.json chartfile.yaml
	jb install
	tk tool charts vendor
	@touch .restore.stamp

restore: .restore.stamp

.PHONY: lint
lint: restore
	tk lint . --parallelism $(shell nproc) --log-level debug

.PHONY: apply
apply: apply-all

.PHONY: apply-all
apply-all: restore
	for env in $(shell tk env list --names); do \
		tk diff $$env -s >/dev/null || tk apply $$env; \
	done

.PHONY: render-test
render-test: restore
	@SHOW_FAIL=0; \
	for env in $(shell tk env list --names); do \
		echo "Checking $$env"; \
		tk show $$env --dangerous-allow-redirect >/dev/null || { \
			echo >&2 "$$env failed to render"; \
			SHOW_FAIL=1; \
		}; \
	done; \
	exit $$SHOW_FAIL

.PHONY: test
test: lint render-test

.PHONY: qolsysgw-build
qolsysgw-build:
	$(MAKE) -C images/qolsysgw build

.PHONY: qolsysgw-push
qolsysgw-push:
	$(MAKE) -C images/qolsysgw push

.PHONY: qolsysgw
qolsysgw: qolsysgw-push
