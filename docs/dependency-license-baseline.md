# Dependency and Model License Baseline

Recorded from `OpenOats/Package.resolved` and the resolved source trees on August 14, 2026. This is an engineering inventory, not legal advice. The complete upstream license text remains authoritative.

## Swift package dependencies

| Package | Resolved version | License observed | Distribution note |
|---|---:|---|---|
| FluidAudio | 0.13.5 | Apache-2.0 | Retain license and notices. |
| LaunchAtLogin-Modern | 1.1.0 | MIT | Retain copyright and permission notice. |
| Sparkle | 2.9.0 | MIT-style plus bundled third-party notices | Preserve the complete Sparkle license file and external notices. |
| WhisperKit | 0.17.0 | MIT | Retain copyright and permission notice. |
| swift-argument-parser | 1.7.1 | Apache-2.0 | Transitive; retain license/notices. |
| swift-asn1 | 1.5.1 | Apache-2.0 | Transitive; retain license/notices. |
| swift-collections | 1.3.0 | Apache-2.0 | Transitive; retain license/notices. |
| swift-crypto | 4.2.0 | Apache-2.0 | Transitive; retain license/notices. |
| swift-jinja | 2.3.2 | Apache-2.0 | Transitive; retain license/notices. |
| swift-transformers | 1.1.9 | Apache-2.0 | Transitive; retain license/notices. |
| yyjson | 0.12.0 | MIT | Transitive; retain copyright and permission notice. |

The top-level fork remains MIT licensed and retains the original OpenOats attribution.

## Model baseline

The application downloads or connects to models at runtime; model weights are not committed in this repository. Code currently exposes Parakeet, Qwen3 ASR, WhisperKit-hosted Whisper variants, Ollama-selected models, and user-selected cloud models.

Rules for the public alpha:

- do not redistribute a model until its exact repository, revision, weight license, and notice obligations are recorded;
- do not infer a weight license from the client library's license;
- keep user-downloaded and API-served models outside the source distribution unless explicitly approved;
- record the model ID and provider used to create preparation artifacts in KnowledgePack provenance;
- flag models with custom, research-only, non-commercial, attribution, or acceptable-use terms for explicit review;
- generate the final SBOM and notices from the locked dependency graph and shipped artifacts, not from this baseline table alone.

## Open items

- Record exact Parakeet and Qwen3 weight repositories and their licenses before packaging either model.
- Record the Whisper weight/model-card terms independently of WhisperKit's MIT library license.
- Decide which, if any, local embedding model is recommended for the first public demonstration and record its exact revision and license.
- Add an automated notice bundle and SBOM check before the open-source release gate.
