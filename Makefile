.DEFAULT_GOAL := help

SCHEME      := mdv
PROJECT     := mdv.xcodeproj
DESTINATION := platform=macOS
DERIVED     := build/DerivedData
HLJS_VERSION ?= 11.12.0
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)
# CI and unsigned local builds: make build SIGN=0
ifeq ($(SIGN),0)
XCODEBUILD += CODE_SIGNING_ALLOWED=NO
endif

.NOTPARALLEL:

.PHONY: help bootstrap generate build test test-core test-app lint format vendor-highlightjs clean

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

test-app: generate ## Run app tests
	$(XCODEBUILD) test

lint: ## Lint with SwiftLint and swift-format
	swiftlint lint --strict
	swift format lint --strict --recursive App AppTests CLI Sources Tests Package.swift

format: ## Auto-format sources
	swift format --in-place --recursive App AppTests CLI Sources Tests Package.swift
	swiftlint lint --fix

vendor-highlightjs: ## Vendor highlight.js (HLJS_VERSION=x.y.z) as generated Swift
	scripts/vendor-highlightjs.sh $(HLJS_VERSION)

clean: ## Remove build artifacts
	rm -rf .build build $(PROJECT)
