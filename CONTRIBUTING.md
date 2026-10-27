# Contributing to Simple Calendar

[English](CONTRIBUTING.md) · [Español](docs/i18n/es/CONTRIBUTING.md)

Simple Calendar is a public project with a [Windows beta release](https://github.com/adribarrios05/simple-calendar/releases/tag/v1.0.0-beta.1). Original code and documentation use the [MIT License](LICENSE.md).

## Issues and pull requests

Use [Issues](https://github.com/adribarrios05/simple-calendar/issues) for bug reports and feature proposals. The bug-report template asks for app/build and Windows versions, reproduction steps and expected/actual behavior. Search existing issues first. Use synthetic examples, redact images and never attach private databases or backups. For changes beyond small fixes, discuss scope in an issue before preparing a focused pull request. Include checks actually executed. Support is best effort; no response deadline is promised.

By submitting an original contribution for inclusion in Simple Calendar, you agree to license it under MIT. Submit only work you authored or have sufficient rights to contribute. Identify third-party code/assets and preserve their original notices and terms; see [third-party components](THIRD_PARTY_NOTICES.md). Contributors retain copyright in their work; no copyright assignment is required.

## Development

Use Windows and the toolchain in [README.md](README.md). Read [AGENTS.md](AGENTS.md) and [ARCHITECTURE.md](ARCHITECTURE.md). Preserve IDs, history, progress, locks/exceptions, the lockfile and storage identity. Keep changes focused and the domain/scheduler pure Dart. Do not add cloud services, accounts or calendar integrations.

Run `flutter analyze` and `flutter test`. Native changes also require the Windows integration test and Release build. Schema changes need transactional migrations and compatibility tests; generate Drift code instead of editing it. Use synthetic data and temporary databases. Never attach real agendas, secrets or private backups to issues.

Report checks actually executed and their limitations. Bug reports should include app/Windows version, reproduction, expected/actual behavior and anonymized evidence. Agent-assisted commits, pushes and publication require a separate explicit request.

## Application languages

English is the default. English templates and Spanish resources live in `lib/l10n/app_strings.dart`, using a Flutter `LocalizationsDelegate`. Material dialogs use Flutter's existing delegates. No additional runtime dependency is needed.

Use `context.strings.text('English template', [arguments])`, adding its Spanish resource. Preserve placeholder indexes. Insert user data only after translation; never translate arbitrary titles, descriptions, subtasks or tag names. Domain/persistence failures remain pure Dart English messages and are localized at display boundaries. IDs, JSON keys and storage paths never depend on language.

Built-in tags keep legacy stored names/IDs. Only untouched built-in labels are translated; renamed/custom labels remain literal. Saving an unchanged localized built-in label preserves its original stored name.

Before enabling another locale, add a complete catalogue, update supported locales/preference validation, and test workflows, Material pickers, placeholders, errors, restart and backup compatibility. The OS locale does not override the English default. If more locales, plurals or date/number formatting outgrow this small catalogue, migrate to standard ARB/gen-l10n resources instead of adding ad hoc grammar rules. See [Flutter internationalization](https://docs.flutter.dev/ui/internationalization).

## Documentation languages

- Root Markdown is the authoritative English source; code comments are English too.
- Translate README and CONTRIBUTING first. Avoid multiplying volatile status/release reports into every language.
- Put translations at `docs/i18n/<language-code>/<SOURCE_FILENAME>.md`. Include language navigation, a source link and last-reviewed date. Future languages use the same structure.
- Update affected translations with source changes when practical; otherwise mark the translation stale and direct readers to current English. Never silently present outdated instructions as current.
- Keep **one authoritative AGENTS.md in English**. Copies named AGENTS.md in subdirectories introduce scoped agent instructions. Any future explanatory translation must use another filename and explicitly state that it is non-authoritative.
- Keep ARCHITECTURE.md as the public English technical contract. Owner-only planning, audits and verification logs belong in the ignored private/ directory; public development must not depend on them.
- Preserve identifiers, commands, limitations and verification dates. Check relative links from the translated file's directory.

This supports English/Spanish now and additional languages later with little duplication. GitHub discovers the root README and contribution guide; language links expose translations without competing root documents.
