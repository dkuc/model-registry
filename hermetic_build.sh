#!/bin/bash
# Builds the async upload job hermetically.
# We should probably move this to the jobs/async-upload/Makefile but
# the pathing is weird because hermeto expects to run in the root of the git repo
set -ex
shopt -s expand_aliases
mkdir -p /tmp/cachi2
alias hermeto='podman run --rm -ti -v "$PWD:$PWD:z" -w "$PWD" -v /tmp/cachi2:/tmp/cachi2 ghcr.io/hermetoproject/hermeto:latest'

hermeto fetch-deps --output /tmp/cachi2/output '[{"type": "rpm", "path": "jobs/async-upload"},{
  "type": "pip", "path": "jobs/async-upload",
  "requirements_files": ["requirements.txt"],
  "requirements_build_files": ["requirements-build.txt","requirements-extra-build-deps.txt"],
  "binary": { "arch": "x86_64", "os": "linux" }
}]'

hermeto inject-files /tmp/cachi2/output --for-output-dir /cachi2/output
hermeto generate-env -f env -o /tmp/cachi2/cachi2.env --for-output-dir /tmp/cachi2 /tmp/cachi2/output

# I'm not sure if this is bug with hermeto - it includes this redirect in the
# package cargo config(/deps/pip/rfc3161_client-1.0.5/rfc3161_client-1.0.5/.cargo/config.toml)
# but not the global cargo config (.cargo/config.toml)
cat >> /tmp/cachi2/output/.cargo/config.toml << 'EOF'

[source."git+https://github.com/pyca/cryptography.git?tag=45.0.4"]
git = "https://github.com/pyca/cryptography.git"
tag = "45.0.4"
replace-with = "local"
EOF

podman build -f jobs/async-upload/Dockerfile.konflux jobs/async-upload/ \
  --volume /tmp/cachi2:/cachi2:Z \
  --volume /tmp/cachi2/output/deps/rpm/x86_64/repos.d:/etc/yum.repos.d \
  --network none \
  --env PIP_NO_BINARY=:all: \
  --env CARGO_HOME=/cachi2/output/.cargo \
  --env PIP_FIND_LINKS=/cachi2/output/deps/pip \
  --env PIP_NO_INDEX=true \
  --build-arg TARGETARCH=x86_64 \
  --tag async-job