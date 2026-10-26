# Third-party components

The [MIT license for Simple Calendar](LICENSE.md) applies to the project's original code and documentation. It does not relicense third-party code, generated/template files carrying other notices, fonts, runtime libraries or other third-party assets. Preserve their original notices and applicable terms.

## Flutter and Dart packages

The Windows build contains Flutter's generated notice bundle at data/flutter_assets/NOTICES.Z. The packaging script preserves that bundle and expands it, without changing its contents, into **THIRD_PARTY_NOTICES.txt** at the ZIP root for reading in a text editor. The text file is generated from the build being packaged, not maintained as a second hand-edited copy.

Examples of direct components reviewed in the resolved package cache (not all shipped components use MIT):

| Component | License family / source |
|---|---|
| Flutter and Flutter localization libraries | BSD-style; [Flutter license](https://github.com/flutter/flutter/blob/master/LICENSE) |
| Riverpod / flutter_riverpod | MIT; [project](https://github.com/rrousselGit/riverpod) |
| Drift | MIT; [project](https://github.com/simolus3/drift) |
| sqlite3 Dart bindings | MIT; [project](https://github.com/simolus3/sqlite3.dart) |
| path | BSD-style; [project](https://github.com/dart-lang/core/tree/main/pkgs/path) |
| path_provider / file_selector and Flutter plugins | BSD-style; [Flutter packages](https://github.com/flutter/packages) |
| uuid | MIT; [project](https://github.com/daegalus/dart-uuid) |

This summary is not the full transitive dependency inventory or a replacement for original license texts. The generated notice bundle supplies the texts collected by Flutter. SQLite itself is distinct from its Dart bindings; see the [SQLite copyright statement](https://www.sqlite.org/copyright.html).

## Windows beta distribution inventory

The local `1.0.0-beta.1` bundle review identified these additional runtime groups:

| Shipped files/assets | Origin and notice handling |
|---|---|
| `flutter_windows.dll`, `data/icudtl.dat`, Flutter assets/shaders | Flutter engine/SDK and its third-party components; preserve the complete generated notice bundle, not just Flutter's top-level BSD license. |
| `file_selector_windows_plugin.dll` | Flutter file-selector plugin; BSD-style terms collected in the bundle. |
| `dartjni.dll` | Dart JNI transitive package native helper; BSD-style package license collected in the bundle. Its presence does not mean a Java installation is required for calendar use. |
| `sqlite3.dll` | Native SQLite selected by the sqlite3 build hook; SQLite is public domain, distinct from the MIT Dart wrapper. |
| `fonts/MaterialIcons-Regular.otf` | Google Material Icons. This Flutter SDK ships a separate **Creative Commons Attribution 4.0 International** notice; packaging preserves it as `licenses/MaterialIcons.txt`. Do not rely on the package notice bundle for this font. Flutter subsets the font during Release builds. Source: [Material Design icons](https://github.com/google/material-design-icons). The current font manifest contains this font, with no custom font assets. |
| App-local `msvcp*`, `vcruntime*`, `concrt140.dll`, `vccorlib140.dll` | Microsoft runtime; separate terms described below. |

This inventory describes the current toolchain output and must be rechecked when dependencies, assets or the native toolchain change. The packaged readable notices are the full texts, not this summary.

## Microsoft Visual C++ runtime

The current script copies app-local VC143 runtime DLLs from the installed Visual Studio redistribution directory. These are Microsoft components governed by the applicable Visual Studio redistribution terms, not by this project's MIT license.

Before public binary distribution, confirm the publisher's redistribution rights and that the actual files appear in the applicable redistributable list:

- [Redistribute Visual C++ files](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files)
- [Visual Studio 2022 distributable code](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution)

The current DLL source directory is `VC/Redist/MSVC/<version>/x64/Microsoft.VC143.CRT`, under the permitted `VC/redist` tree, rather than `debug_nonredist`. Microsoft's list permits unmodified files from that tree subject to the publisher's applicable Visual Studio license terms. The local file/source check does not verify the publisher's license eligibility. Confirm that eligibility before publishing the binary. App-local runtime updates are the publisher's responsibility; rebuild packages when servicing the runtime.

No Microsoft license text or permission is invented or replaced by this document. Readable notices do not establish completed legal clearance, clean-machine validation or readiness to publish.
