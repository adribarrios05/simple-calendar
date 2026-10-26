# Development instructions

## Code discovery

This project uses `codebase-memory-mcp`. Prefer `search_graph`, `trace_path`, `get_code_snippet`, `query_graph` and `get_architecture` for code discovery. Index the repository if needed. Use `rg` for literals, configuration, documentation, or insufficient graph results. Exclude generated code when interpreting the architecture.

## Project rules

- Original project code/documentation use MIT (LICENSE.md). Preserve external/generated code notices and terms. Include project and third-party notices when packaging; do not treat them as completed redistribution clearance.

- Read README.md and ARCHITECTURE.md before changing behavior. When present in the owner's workspace, also read private/CURRENT.md; a public clone must not require private files.
- Windows only. Do not add AI, accounts, a backend, cloud services or calendar integrations.
- Keep the domain and scheduler pure Dart, independent of Flutter and SQLite.
- Preserve IDs and `(taskId, day)` keys. Keep definitions, occurrences and assignments distinct.
- Never discard history, locks, exceptions or progress when recalculating.
- Use minute intervals `[start, end)`, continuous blocks and an injectable clock.
- Show conflicts explicitly. Never silently overwrite protected blocks.
- Every database schema change requires a migration and a test. Never edit `database.g.dart` manually; use `dart run build_runner build`.
- Preserve `pubspec.lock`. Verified SDK: Flutter 3.41.4 / Dart 3.11.1. Drift/drift_dev 2.33.0 are pinned for compatibility.
- Run `flutter analyze` and `flutter test`. Native integration changes also require `flutter test integration_test/windows_test.dart -d windows` and `flutter build windows --release`.
- Use temporary databases and synthetic data in tests. Never seed the normal application or use the user's real database for verification.
- Update private/CURRENT.md with executed checks, limitations and remaining work when that local log is available. Never claim unexecuted validation or publish owner-only notes.
- Do not add external services or unnecessary dependencies. Do not commit, push or publish without a request.
- Write code comments and primary Markdown documentation in English. Historical documents and translations under `docs/` may remain in other languages.
- Localize user-facing text into English and Spanish; English is the default. Never translate user-authored task text, custom/renamed tag names, IDs, JSON keys or storage identity.
- Keep this file as the single authoritative English agent instruction document. Do not add translated `AGENTS.md` copies in subdirectories: they introduce scoped instructions and risk divergence.
- Put human documentation translations under `docs/i18n/<language-code>/`. Link to the English source and review date; see CONTRIBUTING.md.

Distribution uses `scripts/package_windows.ps1`. `dist`, `build` and `artifacts` are ignored local outputs. Preserve unrelated edits. Do not close a running user application to run tests without agreement.
