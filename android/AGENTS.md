# Android package instructions

- Keep library code in `scummvm/` and sample-only behavior in `app/`; the upstream engine is the repository-root `../scummvm/` submodule.
- Never edit upstream or generated files under `**/build/`.
- Preserve upstream `configure`/`make`, Java staging, `org.scummvm.scummvm` JNI names, NDK r28+ support, and one engine host per process.
- Keep the library manifest consumer-neutral and public Compose API small unless explicitly requested otherwise.
- Validate Kotlin/Compose changes with a focused library build and sample build.
- Validate releases by building `:scummvm:assembleRelease`, consuming the produced AAR in `:app:assembleRelease`, and inspecting required native libraries and runtime assets.
- Keep `README.md` current when prerequisites, Gradle properties, public API, packaging, or limitations change.
- Apply `android-compose-development`, `android-build-triage`, or `android-release-checks` from `../.agents/skills/` as appropriate.
