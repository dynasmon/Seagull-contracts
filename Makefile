SHELL := /bin/bash
GO ?= go
LOCAL_BIN := $(CURDIR)/.local/bin

export PATH := $(LOCAL_BIN):$(PATH)

.PHONY: help lint generate check breaking build mod-check clean verify

help:
	@echo "lint       check the contracts against the style rules"
	@echo "generate   regenerate the Go bindings"
	@echo "check      fail when the committed bindings are stale"
	@echo "breaking   fail when a change breaks compatibility with main"
	@echo "build      compile the generated bindings"
	@echo "mod-check  verify the dependency graph and checksums"
	@echo "verify     lint, mod-check, check and build"

$(LOCAL_BIN)/buf $(LOCAL_BIN)/protoc-gen-go:
	cd tools/buf && GOBIN=$(LOCAL_BIN) $(GO) install github.com/bufbuild/buf/cmd/buf
	cd tools/buf && GOBIN=$(LOCAL_BIN) $(GO) install google.golang.org/protobuf/cmd/protoc-gen-go

lint: $(LOCAL_BIN)/buf
	buf lint

generate: $(LOCAL_BIN)/buf $(LOCAL_BIN)/protoc-gen-go
	buf generate

check: generate
	@if ! git diff --quiet -- gen; then \
	  echo "the committed bindings are stale; run make generate and commit the result"; \
	  git --no-pager diff --stat -- gen; exit 1; \
	fi

# The baseline is the remote-tracking ref rather than a local branch. Fetching
# into `refs/heads/main` is refused whenever main happens to be checked out,
# which is a property of the workspace and not of the contracts, and it is what
# broke this check in CI; a remote-tracking ref is never checked out, so it can
# always be fetched and always be read. A local main is still accepted, for a
# working copy that has one and no remote.
breaking: $(LOCAL_BIN)/buf
	@baseline=origin/main; \
	git rev-parse --verify --quiet "$$baseline" >/dev/null || baseline=main; \
	git rev-parse --verify --quiet "$$baseline" >/dev/null || \
	  { echo "no baseline to compare against; run: git fetch origin main"; exit 1; }; \
	if [ -z "$$(git ls-tree -r --name-only "$$baseline" -- proto)" ]; then \
	  echo "$$baseline carries no contracts yet; nothing to compare against"; \
	else \
	  echo "comparing against $$baseline"; \
	  buf breaking --against ".git#ref=$$baseline"; \
	fi

build:
	$(GO) build ./...

mod-check:
	$(GO) mod verify
	@tmp="$$(mktemp -d)"; cp go.mod go.sum "$$tmp/"; status=0; \
	$(GO) mod tidy || status=1; \
	diff -u "$$tmp/go.mod" go.mod || status=1; \
	diff -u "$$tmp/go.sum" go.sum || status=1; \
	cp "$$tmp/go.mod" go.mod; cp "$$tmp/go.sum" go.sum; rm -rf "$$tmp"; exit "$$status"

clean:
	rm -rf $(LOCAL_BIN)

verify: lint mod-check check build
