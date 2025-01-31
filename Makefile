.PHONY: diff
diff:
	tk diff environments/default

.PHONY: restore
restore:
	jb install
	tk tool charts vendor

.PHONY: apply
apply:
	tk apply environments/default
