#!/bin/sh

set -e

DOCKER_BAKE_FILE=${1:-"docker-bake.hcl"}
IMAGE_NAME=${IMAGE_NAME:-"prodrigestivill/postgres-backup-local"}

GOCRONVER="v0.0.10"
MAIN_TAG="14"
TAGS_EXTRA="13 12"
PLATFORMS="linux/amd64 linux/arm64 linux/arm/v7 linux/s390x linux/ppc64le"
TAGS_EXTRA_2="11 10"
PLATFORMS_DEBIAN_2="linux/amd64 linux/arm64 linux/arm/v7"


cd "$(dirname "$0")"

P="\"$(echo $PLATFORMS | sed 's/ /", "/g')\""
P2="\"$(echo $PLATFORMS_DEBIAN_2 | sed 's/ /", "/g')\""

T="\"debian-latest\", \"alpine-latest\", \"$(echo debian-$TAGS_EXTRA $TAGS_EXTRA_2 | sed 's/ /", "debian-/g')\", \"$(echo alpine-$TAGS_EXTRA $TAGS_EXTRA_2 | sed 's/ /", "alpine-/g')\""

cat > "$DOCKER_BAKE_FILE" << EOF
group "default" {
	targets = [$T]
}

variable "BUILDREV" {
	default = ""
}

target "debian" {
	args = {"GOCRONVER" = "$GOCRONVER"}
	dockerfile = "debian.Dockerfile"
}

target "alpine" {
	args = {"GOCRONVER" = "$GOCRONVER"}
	dockerfile = "alpine.Dockerfile"
}

target "debian-latest" {
	inherits = ["debian"]
	platforms = [$P]
	args = {"BASETAG" = "$MAIN_TAG"}
	tags = [
		"$IMAGE_NAME:latest",
		"$IMAGE_NAME:$MAIN_TAG",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$MAIN_TAG-debian-\${BUILDREV}" : ""
	]
}

target "alpine-latest" {
	inherits = ["alpine"]
	platforms = [$P]
	args = {"BASETAG" = "$MAIN_TAG-alpine"}
	tags = [
		"$IMAGE_NAME:alpine",
		"$IMAGE_NAME:$MAIN_TAG-alpine",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$MAIN_TAG-alpine-\${BUILDREV}" : ""
	]
}
EOF

for TAG in $TAGS_EXTRA; do cat >> "$DOCKER_BAKE_FILE" << EOF

target "debian-$TAG" {
	inherits = ["debian"]
	platforms = [$P]
	args = {"BASETAG" = "$TAG"}
	tags = [
		"$IMAGE_NAME:$TAG",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$TAG-debian-\${BUILDREV}" : ""
	]
}

target "alpine-$TAG" {
	inherits = ["alpine"]
	platforms = [$P]
	args = {"BASETAG" = "$TAG-alpine"}
	tags = [
		"$IMAGE_NAME:$TAG-alpine",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$TAG-alpine-\${BUILDREV}" : ""
	]
}
EOF
done

for TAG in $TAGS_EXTRA_2; do cat >> "$DOCKER_BAKE_FILE" << EOF

target "debian-$TAG" {
	inherits = ["debian"]
	platforms = [$P2]
	args = {"BASETAG" = "$TAG"}
	tags = [
		"$IMAGE_NAME:$TAG",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$TAG-debian-\${BUILDREV}" : ""
	]
}

target "alpine-$TAG" {
	inherits = ["alpine"]
	platforms = [$P]
	args = {"BASETAG" = "$TAG-alpine"}
	tags = [
		"$IMAGE_NAME:$TAG-alpine",
		notequal("", BUILDREV) ? "$IMAGE_NAME:$TAG-alpine-\${BUILDREV}" : ""
	]
}
EOF
done
