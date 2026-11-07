.DEFAULT_GOAL := help

SCHEME      := mdv
PROJECT     := mdv.xcodeproj
DESTINATION := platform=macOS
DERIVED     := build/DerivedData
# UI test results (screenshots, logs): open in Xcode to debug a failure.
UI_RESULT   := build/AppUITests.xcresult
HLJS_VERSION ?= 11.12.0
# sindresorhus/github-markdown-css release the GitHub theme is generated from.
GHCSS_VERSION ?= 5.9.0
XCODEBUILD_BASE := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)
XCODEBUILD  := $(XCODEBUILD_BASE)
# github/gemoji commit the emoji table is generated from (`make emoji`).
GEMOJI_COMMIT := fadaeaf1f1a9be82b321316a6c5502e43138b2f6
GEMOJI_JSON   := build/gemoji/emoji-$(GEMOJI_COMMIT).json
EMOJI_TABLE   := Sources/MdvCore/Generated/EmojiTable.swift
ENTITIES_JSON := build/html-entities/entities.json
ENTITY_TABLE  := Sources/MdvCore/Generated/HTMLEntityTable.swift
# CI and unsigned local builds: make build SIGN=0
ifeq ($(SIGN),0)
XCODEBUILD += CODE_SIGNING_ALLOWED=NO
endif
# UI tests always sign: Gatekeeper refuses to run an unsigned UI test runner. SIGN is ignored;
# sign with the team in Config/Local.xcconfig if present, else ad hoc ("Sign to Run Locally").
ifneq ($(wildcard Config/Local.xcconfig),)
XCODEBUILD_UI := $(XCODEBUILD_BASE)
else
XCODEBUILD_UI := $(XCODEBUILD_BASE) CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
endif

.NOTPARALLEL:

.PHONY: help bootstrap generate build test test-core test-app test-ui lint format emoji html-entities vendor-highlightjs vendor-github-markdown-css clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

bootstrap: ## Install required tools via Homebrew
	brew install xcodegen swiftlint

generate: ## Generate mdv.xcodeproj from project.yml
	xcodegen generate

build: generate ## Build the app and CLI
	$(XCODEBUILD) build

test: test-core test-app ## Run all tests

test-core: ## Run MdvCore package tests
	swift test

test-app: generate ## Run app unit tests (hosted, no UI automation)
	$(XCODEBUILD) test -only-testing:AppTests

test-ui: generate ## Run UI tests (always signed; see CLAUDE.md)
	rm -rf $(UI_RESULT)
	$(XCODEBUILD_UI) test -only-testing:AppUITests -resultBundlePath $(UI_RESULT)

lint: ## Lint with SwiftLint and swift-format
	swiftlint lint --strict
	swift format lint --strict --recursive App AppTests AppUITests CLI Sources Tests Package.swift

format: ## Auto-format sources
	swift format --in-place --recursive App AppTests AppUITests CLI Sources Tests Package.swift
	swiftlint lint --fix

emoji: ## Regenerate the emoji shortcode table from github/gemoji at GEMOJI_COMMIT
	mkdir -p $(dir $(GEMOJI_JSON)) $(dir $(EMOJI_TABLE))
	curl -fsSL "https://raw.githubusercontent.com/github/gemoji/$(GEMOJI_COMMIT)/db/emoji.json" -o $(GEMOJI_JSON)
	swift scripts/generate-emoji.swift $(GEMOJI_JSON) $(GEMOJI_COMMIT) $(EMOJI_TABLE)

html-entities: ## Regenerate the HTML named character reference table from the WHATWG list
	mkdir -p $(dir $(ENTITIES_JSON)) $(dir $(ENTITY_TABLE))
	curl -fsSL "https://html.spec.whatwg.org/entities.json" -o $(ENTITIES_JSON)
	swift scripts/generate-html-entities.swift $(ENTITIES_JSON) $(ENTITY_TABLE)

vendor-highlightjs: ## Vendor highlight.js (HLJS_VERSION=x.y.z) as generated Swift
	scripts/vendor-highlightjs.sh $(HLJS_VERSION)

vendor-github-markdown-css: ## Vendor github-markdown-css (GHCSS_VERSION=x.y.z) as generated Swift
	scripts/vendor-github-markdown-css.sh $(GHCSS_VERSION)

clean: ## Remove build artifacts
	rm -rf .build build $(PROJECT)
