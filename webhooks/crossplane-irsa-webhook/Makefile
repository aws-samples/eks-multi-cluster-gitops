export CGO_ENABLED=0
export T=github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook
UNAME_S = $(shell uname -s)
GO_LDFLAGS = -ldflags='-s -w -buildid=""'

install:: build
ifeq ($(UNAME_S), Darwin)
	GOOS=darwin GOARCH=amd64 go build -o build/gopath/bin/darwin_amd64/crossplane-irsa-webhook $(GO_LDFLAGS) $V $T
endif
	GOOS=linux GOARCH=amd64 go build -o build/gopath/bin/linux_amd64/crossplane-irsa-webhook $(GO_LDFLAGS) $V $T

# Generic make
# Dummy account ID. Replace with actual account ID.
ACCOUNT_ID?=012345678901
# Create ECR repo before running the build
IMAGE_NAME?=multi-cluster-gitops/crossplane-irsa-webhook
# Update the region
AWS_REGION?=eu-west-1
IMAGE?=$(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE_NAME)

test:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out

docker:
	@echo 'Building image $(IMAGE)...'
	docker build --no-cache -t $(IMAGE) .

push: docker
	if ! aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com; then \
		eval $$(aws ecr get-login --registry-ids $(ACCOUNT_ID) --no-include-email); \
	fi
	docker push $(IMAGE)

crossplane-irsa-webhook:
	go build

certs/tls.key:
	mkdir -p certs
	openssl req \
		-x509 \
		-newkey rsa:2048 \
		-keyout certs/tls.key \
		-out certs/tls.crt \
		-days 365 \
		-nodes \
		-subj "/CN=127.0.0.1"

local-serve: crossplane-irsa-webhook certs/tls.key
	./crossplane-irsa-webhook \
		--port 8443 \
		--in-cluster=false \
		--tls-key=./certs/tls.key \
		--tls-cert=./certs/tls.crt \
		--kubeconfig=$$HOME/.kube/config

local-request:
	@curl \
		-s \
		-k \
		-H "Content-Type: application/json" \
		-X POST \
		-d @hack/request.json
		https://localhost:8443/mutate | jq

# cluster commands
cluster-up: deploy-config

cluster-down: delete-config

prep-config:
	@echo 'Generating certs and deploying into active cluster...'
	cat deploy/deployment-base.yaml | sed -e "s|IMAGE|${IMAGE}|g" | tee deploy/deployment.yaml
	cat deploy/mutatingwebhook.yaml | hack/webhook-patch-ca-bundle.sh > deploy/mutatingwebhook-ca-bundle.yaml

deploy-config: prep-config
	@echo 'Applying configuration to active cluster...'
	kubectl apply -f deploy/auth.yaml
	kubectl apply -f deploy/deployment.yaml
	kubectl apply -f deploy/service.yaml
	kubectl apply -f deploy/mutatingwebhook-ca-bundle.yaml
	until kubectl get csr -o \
		jsonpath='{.items[?(@.spec.username=="system:serviceaccount:crossplane-system:crossplane-irsa-webhook")].metadata.name}' | \
		grep -m 1 "csr-"; \
		do echo "Waiting for CSR to be created" && sleep 1 ; \
	done
	kubectl certificate approve $$(kubectl get csr -o jsonpath='{.items[?(@.spec.username=="system:serviceaccount:crossplane-system:crossplane-irsa-webhook")].metadata.name}')

delete-config:
	@echo 'Tearing down mutating controller and associated resources...'
	kubectl delete -f deploy/mutatingwebhook-ca-bundle.yaml
	kubectl delete -f deploy/service.yaml
	kubectl delete -f deploy/deployment.yaml
	kubectl delete -f deploy/auth.yaml
	kubectl delete secret crossplane-irsa-webhook

clean::
	rm -rf ./crossplane-irsa-webhook
	rm -rf ./certs/ coverage.out

.PHONY: docker push build local-serve local-request cluster-up cluster-down prep-config deploy-config delete-config clean
