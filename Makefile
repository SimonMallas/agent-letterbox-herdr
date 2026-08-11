.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/test_lifecycle_v02.sh
	./tests/herdr-doorbell-safety.sh
	./tests/test_herdr_bootstrap.sh

ci: test
