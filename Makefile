.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/test_no_private_data.sh
	./tests/test_private_vocabulary.sh
	./tests/test_release_text.sh
	./tests/test_lifecycle_v02.sh
	./tests/test_lifecycle_v03.sh
	./tests/test_resolver_v03.sh
	./tests/test_doorbell_v03.sh
	./tests/test_check_v03.sh
	./tests/test_confirm_v03.sh
	./tests/herdr-doorbell-safety.sh
	./tests/test_herdr_bootstrap.sh

ci: test
