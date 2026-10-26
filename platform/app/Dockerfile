# syntax=docker/dockerfile:1.7
# Multi-stage build â†’ small, non-root, no shell in the final image.

FROM golang:1.26-alpine AS builder

WORKDIR /src

# Cache module download before copying the source.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG VERSION=dev
ARG COMMIT=none

# CGO disabled â†’ fully static binary; -s -w strips symbols/debug to shrink the image.
RUN go vet ./... && go test ./...

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
    -o /out/myapp \
    ./

# Distroless static â€” no shell, no package manager, runs as nonroot.
# Production-grade base; smaller blast radius than alpine.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/myapp /app/myapp

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/myapp"]
