.PHONY: test build package check

test:
	/bin/bash tests/run.sh

build:
	/bin/bash scripts/build.sh

package:
	/bin/bash scripts/package.sh

check:
	/bin/bash scripts/check.sh
