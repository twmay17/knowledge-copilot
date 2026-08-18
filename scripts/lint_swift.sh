#!/usr/bin/env bash
# Strict swift-format lint over the sources that follow the repository's
# canonical (swift-format default, 2-space) style. Legacy 4-space files
# (Settings, Views, Intelligence, app scaffolding, and their tests) predate
# the convention: they are excluded here, must not gain new violation
# categories in review, and migrate as they are rewritten.
set -euo pipefail
cd "$(dirname "$0")/../OpenOats"

swift format lint --strict --recursive \
  Sources/OpenOats/KnowledgePack \
  Sources/OpenOats/Utils/SensitiveDataGuard.swift \
  Sources/DomainProfiles \
  Sources/KnowledgePackTool \
  Sources/AudioCaptureVerificationTool \
  Sources/TeamsAlphaReviewTool

# KnowledgeBaseTests.swift matches the Knowledge* prefix but predates this
# wave (last touched in upstream PR #354, before the 2-space convention);
# it is still 4-space legacy end-to-end. Excluded here as legacy.
knowledge_test_files=()
for f in Tests/OpenOatsTests/Knowledge*.swift; do
  if [[ "$f" != "Tests/OpenOatsTests/KnowledgeBaseTests.swift" ]]; then
    knowledge_test_files+=("$f")
  fi
done
swift format lint --strict "${knowledge_test_files[@]}"

echo "lint_swift: clean"
