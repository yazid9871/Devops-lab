.PHONY: help check install access deploy open test publish backup restore monitoring grafana grafana-password trust-ca test-rate-limit
help check install access deploy open test publish backup restore monitoring grafana grafana-password trust-ca test-rate-limit:
	bash scripts/lab.sh $@
