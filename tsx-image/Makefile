.PHONY: build publish

VERSION=1.0.0
REGISTRY=gleif
IMAGE=tsx
LATEST_TAG=$(REGISTRY)/$(IMAGE):latest
VERSIONED_TAG=$(REGISTRY)/$(IMAGE):$(VERSION)

build:
	@docker build \
		--platform=linux/amd64,linux/arm64 \
		-f Dockerfile \
		-t $(VERSIONED_TAG) \
		-t $(LATEST_TAG) .

publish:
	@docker push $(REGISTRY)/$(IMAGE) --all-tags