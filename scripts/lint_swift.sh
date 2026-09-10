#!/usr/bin/env bash
# Strict swift-format lint over the sources that follow the repository's
# canonical (swift-format default, 2-space) style. Legacy 4-space files
# (Settings, Views, Intelligence, app scaffolding, and their tests) predate
# the convention: they are excluded here, must not gain new violation
# categories in review, and migrate as they are rewritten.
set -euo pipefail
# An unmatched glob must expand to nothing, not fall through to the literal
# pattern string — see the zero-match file-count assertion below.
shopt -s nullglob
cd "$(dirname "$0")/../OpenOats"

strict_source_paths=(
  Sources/OpenOats/KnowledgePack
  Sources/OpenOats/Utils/SensitiveDataGuard.swift
  Sources/OpenOats/Whiteboard/SidecastWhiteboardCoordinator.swift
  Sources/OpenOats/Whiteboard/WhiteboardSessionArchive.swift
  Sources/OpenOats/Whiteboard/WhiteboardPackReadiness.swift
  Sources/DomainProfiles
  Sources/KnowledgePackTool
  Sources/AudioCaptureVerificationTool
  Sources/TeamsAlphaReviewTool
)
swift format lint --strict --recursive "${strict_source_paths[@]}"

# KnowledgeBaseTests.swift matches the Knowledge* prefix but predates this
# wave (last touched in upstream PR #354, before the 2-space convention);
# it is still 4-space legacy end-to-end. Excluded here as legacy.
# HospitalityUnderwritingImporterTests.swift is wave-touched and already
# 2-space, but doesn't match the Knowledge* prefix, so it's added explicitly.
knowledge_test_files=(
  Tests/OpenOatsTests/HospitalityUnderwritingImporterTests.swift
  Tests/OpenOatsTests/SidecastWhiteboardCoordinatorTests.swift
)
knowledge_glob_matches=0
for f in Tests/OpenOatsTests/Knowledge*.swift; do
  if [[ "$f" != "Tests/OpenOatsTests/KnowledgeBaseTests.swift" ]]; then
    knowledge_test_files+=("$f")
    knowledge_glob_matches=$((knowledge_glob_matches + 1))
  fi
done
swift format lint --strict "${knowledge_test_files[@]}"

# `swift format lint --recursive` over a nonexistent/renamed directory, or a
# glob that (without nullglob) expands to its own unmatched literal pattern
# string, both exit 0 silently — verified empirically. Trusting that exit
# code alone would let a broken path silently report "clean" without ever
# linting anything. Count each group independently of swift-format's own
# verdict, and independently of each other: the strict_source_paths group
# always has files in this repo, so a combined total would mask the
# Knowledge* glob specifically matching zero — check it on its own.
strict_source_file_count=$(find "${strict_source_paths[@]}" -name '*.swift' -type f | wc -l | tr -d ' ')
if [[ "$strict_source_file_count" -eq 0 ]]; then
  echo "lint_swift: FAILED — zero files found under strict_source_paths; a path is likely broken" >&2
  exit 1
fi
if [[ "$knowledge_glob_matches" -eq 0 ]]; then
  echo "lint_swift: FAILED — the Knowledge*.swift glob matched zero files; it is likely broken" >&2
  exit 1
fi

echo "lint_swift: clean"
