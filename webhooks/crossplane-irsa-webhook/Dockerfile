FROM golang:1.18.3 AS builder

ARG GOVERSION=go1.18.3
# BUILD_TYPE should be one of (dev, release).
ARG BUILD_TYPE=release
ARG GIT_SHA="<NO COMMIT HASH>"
ARG BUILD_INFO_IMPORT_PATH=github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook/pkg/version
ARG VERSION=v0.1.0

WORKDIR $GOPATH/src/github.com/aws-samples/multi-cluster-gitops-crossplane-irsa-webhook
COPY . ./
RUN apt update && apt install ca-certificates libgnutls30 -y && \
    GOPROXY=direct CGO_ENABLED=0 GOOS=linux go build \
    -o /webhook \
    -v \
    -a \
    -installsuffix nocgo \
    -ldflags "-X $BUILD_INFO_IMPORT_PATH.GitCommit=$GIT_SHA -X $BUILD_INFO_IMPORT_PATH.Version=$VERSION -X $BUILD_INFO_IMPORT_PATH.BuildType=$BUILD_TYPE -X $BUILD_INFO_IMPORT_PATH.GoVersion=$GOVERSION -s -w -buildid=''" \
    .

FROM scratch
COPY --from=builder /webhook /webhook
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 443
VOLUME /etc/webhook
ENTRYPOINT ["/webhook"]
CMD ["--logtostderr"]