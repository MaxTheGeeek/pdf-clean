# PDFClean — every build, test and verification entry point.
# macOS with Xcode 16+ required for build/test targets. `make help` lists targets.

PKG      := Packages/PDFCleanKit
PROJECT  := PDFClean.xcodeproj
VENV     := .venv
PY       := $(VENV)/bin/python
OUT      := .build-out
# First available iPhone simulator (override: make test-ios SIM_ID=<udid>)
SIM_ID   ?= $(shell xcrun simctl list devices available 2>/dev/null | grep -m1 -E '^[[:space:]]+iPhone' | grep -oE '[0-9A-F-]{36}')

.DEFAULT_GOAL := help
.PHONY: help bootstrap generate build test build-mac build-ios test-ios run-cli e2e \
        format lint check-offline check-specs verify coverage fixtures fixtures-verify clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

bootstrap: ## Install dev tools (XcodeGen) and the Python fixture venv
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -d $(VENV) || python3 -m venv $(VENV)
	@$(PY) -m pip install -q -r scripts/fixtures/requirements.txt
	@echo "bootstrap ok"

generate: ## Generate PDFClean.xcodeproj from project.yml
	xcodegen generate --spec project.yml

build: ## Build the Swift package (library + CLI)
	swift build --package-path $(PKG)

test: ## Run all package tests (unit + fixture suites)
	swift test --package-path $(PKG)

build-mac: generate ## Build the macOS app (Debug)
	xcodebuild -project $(PROJECT) -scheme PDFClean-macOS -configuration Debug -destination 'platform=macOS' build | tail -n 20

build-ios: generate ## Build the iOS app for the simulator (Debug)
	xcodebuild -project $(PROJECT) -scheme PDFClean-iOS -configuration Debug -destination 'generic/platform=iOS Simulator' build | tail -n 20

test-ios: ## Run package tests on an iOS simulator
	@test -n "$(SIM_ID)" || (echo "No iPhone simulator found; install one in Xcode > Settings > Components" && exit 1)
	cd $(PKG) && xcodebuild test -scheme PDFCleanKit -destination 'id=$(SIM_ID)' | tail -n 30

run-cli: ## Run the CLI: make run-cli ARGS="input.pdf -o out.md --report r.json"
	swift run --package-path $(PKG) pdfclean $(ARGS)

e2e: build ## CLI end-to-end over all fixtures (TC-E01)
	@mkdir -p $(OUT)
	./scripts/e2e.sh

format: ## Format Swift sources in place
	swift format --in-place --recursive --configuration .swift-format $(PKG)/Sources $(PKG)/Tests App

lint: ## Lint Swift sources (fails on violations)
	swift format lint --strict --recursive --configuration .swift-format $(PKG)/Sources $(PKG)/Tests App

check-offline: ## Gate: no network APIs, no network entitlements, logging only via Log (NFR-01/02)
	./scripts/check_offline.sh

check-specs: ## Gate: requirement ↔ test ↔ task traceability
	python3 scripts/check_specs.py

verify: check-specs check-offline lint test ## Everything a task must pass before it is done

coverage: ## Code coverage of PDFCleanKit (gate 80 %, TC-Q01)
	swift test --package-path $(PKG) --enable-code-coverage
	@xcrun llvm-cov report $$(swift build --package-path $(PKG) --show-bin-path)/PDFCleanKitPackageTests.xctest/Contents/MacOS/PDFCleanKitPackageTests \
	  -instr-profile $$(swift build --package-path $(PKG) --show-bin-path)/codecov/default.profdata \
	  -ignore-filename-regex='(Tests|\.build)/' | tail -n 1

fixtures: ## Regenerate fixture PDFs and manifest.json (needs `make bootstrap`)
	$(PY) scripts/fixtures/generate_fixtures.py
	$(PY) scripts/fixtures/build_manifest.py

fixtures-verify: ## Prove fixtures contain what the manifest claims (independent extractors)
	$(PY) scripts/fixtures/verify_fixtures.py
	$(PY) -I scripts/reference/visibility_reference.py --check

clean: ## Remove build products and generated project
	rm -rf $(PKG)/.build $(PROJECT) $(OUT)
