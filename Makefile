.PHONY: all check lint format test package

all: check test

check: lint
	stylua --check .

lint:
	luacheck .

format:
	stylua .

test:
	lua5.1 tests/run.lua
	lua5.1 tests/ui.lua

# Build the CurseForge zip locally without uploading anything.
package:
	curl -sL https://raw.githubusercontent.com/BigWigsMods/packager/v2.5.1/release.sh -o /tmp/brg-release.sh
	chmod +x /tmp/brg-release.sh
	/tmp/brg-release.sh -d -t .
