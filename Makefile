.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/test_herdr_bootstrap.sh

ci: test
