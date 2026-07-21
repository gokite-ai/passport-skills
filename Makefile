.PHONY: bump-up bump-down

# Bump patch version by default, or major with: make bump-up MAJOR=1
bump-up:
ifdef MAJOR
	bash scripts/bump-version.sh --major
else
	bash scripts/bump-version.sh
endif
	npm install

# Decrement patch version by default, or major with: make bump-down MAJOR=1
bump-down:
ifdef MAJOR
	bash scripts/bump-version.sh --down --major
else
	bash scripts/bump-version.sh --down
endif
	npm install
