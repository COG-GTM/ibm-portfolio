#!/usr/bin/env bash
# Regenerate the architecture diagram images from architecture.dot (needs Graphviz: apt-get install graphviz).
set -euo pipefail
cd "$(dirname "$0")"
dot -Tpng -Gdpi=110 architecture.dot -o architecture.png
dot -Tsvg architecture.dot -o architecture.svg
echo "Rendered architecture.png and architecture.svg"
