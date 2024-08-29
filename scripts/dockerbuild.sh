#!/bin/bash

# Check if the first argument is "clean"
if [ "$1" == "clean" ]; then
  NO_CACHE="--no-cache"
else
  NO_CACHE=""
fi

echo "Building njs-surface:multistage"
docker build $NO_CACHE --tag njs-surface:multistage --tag docker.repo1.uhc.com/orx-dso-tools-suite/devdays/njs-surface:multistage --file surfaces/njs-surface/Dockerfile .

echo "Building njs-surface:base"
docker build --tag njs-surface:base  --tag docker.repo1.uhc.com/orx-dso-tools-suite/devdays/njs-surface:base --file surfaces/njs-surface/Dockerfile --target base .

echo "Building njs-surface:copier"
docker build --tag njs-surface:copier  --tag docker.repo1.uhc.com/orx-dso-tools-suite/devdays/njs-surface:copier --file surfaces/njs-surface/Dockerfile --target copier .

echo "Building njs-surface:builder"
docker build --tag njs-surface:builder  --tag docker.repo1.uhc.com/orx-dso-tools-suite/devdays/njs-surface:builder --file surfaces/njs-surface/Dockerfile --target builder .

echo "Building njs-surface:singlestage"
docker build $NO_CACHE --tag njs-surface:singlestage  --tag docker.repo1.uhc.com/orx-dso-tools-suite/devdays/njs-surface:singlestage --file surfaces/njs-surface/Dockerfile_1 .
