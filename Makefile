.PHONY: diff
diff:
	tk diff environments/default

.PHONY: restore
restore:
	jb install
	tk tool charts vendor

.PHONY: apply
apply: apply-all

.PHONY: apply-all
apply-all:
	for env in $(shell tk env list --names); do \
		tk diff $$env -s >/dev/null || tk apply $$env; \
	done
