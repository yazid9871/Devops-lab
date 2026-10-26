PYTHON ?= python3
LAB = $(PYTHON) scripts/platform_lab.py

.PHONY: help tools check bootstrap cluster-create dev-image status verify argocd-ui argocd-password grafana-password backup test-restore test-normal test-burst test-flood test-recovery test-spoof test-two-clients
help:
	@$(LAB) --help
tools check bootstrap cluster-create dev-image status verify argocd-ui argocd-password grafana-password backup test-restore:
	$(LAB) $@
test-normal test-burst test-flood test-recovery test-spoof test-two-clients:
	$(LAB) test-traffic --scenario $(patsubst test-%,%,$@)
