.PHONY: build-signify publish-signify

VERSION=1.0.0
REGISTRY=gleif
IMAGE=vlei-workflow-signify
LATEST_TAG=$(REGISTRY)/$(IMAGE):latest
VERSIONED_TAG=$(REGISTRY)/$(IMAGE):$(VERSION)

build-signify:
	@docker build \
		--platform=linux/amd64,linux/arm64 \
		-f signify-ts.Dockerfile \
		-t $(VERSIONED_TAG) \
		-t $(LATEST_TAG) .

publish-signify:
	@docker push $(REGISTRY)/$(IMAGE) --all-tags