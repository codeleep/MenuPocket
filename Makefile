.PHONY: build test check package screenshots ci
build:
	bash scripts/build.sh

test:
	bash scripts/test.sh

check:
	python3 scripts/check.py
	@for script in scripts/*.sh; do bash -n "$$script" || exit; done

package: build
	bash scripts/package.sh

screenshots:
	bash scripts/screenshots.sh

ci: check test
	bash scripts/build.sh --arch universal --sign adhoc --output dist/ci
	bash scripts/package.sh dist/ci
