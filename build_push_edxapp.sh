#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly EDX_PLATFORM_REPOSITORY="https://github.com/openedx/edx-platform.git"
readonly EDX_PLATFORM_VERSION="open-release/maple.master"

if [ ! -d "./openedx/edx-platform" ]; then
  mkdir -p ./openedx/edx-platform
  git clone $EDX_PLATFORM_REPOSITORY --branch $EDX_PLATFORM_VERSION --depth 1 ./openedx/edx-platform
else
  git -C ./openedx/edx-platform pull
fi
cp ./build_assets/build_assets_cms.py ./openedx/edx-platform/cms/envs/assets.py
cp ./build_assets/build_assets_lms.py ./openedx/edx-platform/lms/envs/assets.py

cat ./build_assets/production_logger_settings.py >> ./openedx/edx-platform/cms/envs/production.py
cat ./build_assets/production_logger_settings.py >> ./openedx/edx-platform/lms/envs/production.py

GIT_COMMIT=$(git -C ./openedx/edx-platform rev-parse HEAD)
docker build -f Dockerfile -t mitodl/edxapp:latest -t mitodl/edxapp:$GIT_COMMIT ./openedx/edx-platform
docker push mitodl/edxapp:$GIT_COMMIT && docker push mitodl/edxapp:$GIT_COMMIT
echo "Edx Image mitodl/edxapp:${GIT_COMMIT} Pushed Successfully"
