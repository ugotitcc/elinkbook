# Progress Ledger

- [x] Task 1: Scaffolding & Router (complete, commits 310c119..61a5d65, review clean)
- [x] Task 2: Shelf & Fulltext Search (complete, commits 61a5d65..19e751a, review clean)
- [x] Task 3: Vertical Writing & Page Styles (complete, commits 19e751a..f61e3d0, review clean)
- [x] Task 4: Navigation Zones (complete, commits f61e3d0..ebef71e, review clean)
- [x] Task 5: Annotations & Markdown Export (complete, commits ebef71e..09552d8, review clean)
- [x] Task 6: Heatmap & Activity Timer (complete, commits 09552d8..6251a03, review clean)
- [x] Task 7: Cloud Sync & Conflict Dialog (complete, commits 6251a03..7c23b33, review clean)
- [x] Task 2: TXT 封面產生器 (complete, commits 1c1f976..eed3d17, review clean; Minor notes: test3 doesn't isolate color logic specifically, buffer.asUint8List() latent fragility -- both inherited from plan's prescribed code, not implementer faults)
- [x] Task 3: BookImportService importFiles pipeline (complete, commits eed3d17..fd052a2, review clean; 1 Important doc-inconsistency finding resolved by fixing spec.md/design.md/plan-issue-4.md to match the already-correct code, commits 7f58d2f + merge 594cde7)
- [x] Task 1: FileProvider + 原生測試方法 + 真正 content:// 驗收測試 (complete, commits 594cde7..2bba316, review clean)
- [x] Task 4: 手動端到端驗收 (complete, commits 2bba316..b4a1649, done directly by controller not subagent due to real human-in-loop interaction requirement; manually verified 3 real files imported successfully on real device via workaround for integration_test/instrumentation file-picker limitation)
- [x] Task 4 review clean (Approved, no Critical/Important)
- [x] Final whole-branch review: Ready to merge with 1 Important finding (`kotlin.incremental=false` set globally in `app/android/gradle.properties`, penalizes all platforms/CI for a Windows-only cross-drive-letter bug). User decision: scope to Windows only (not leave as global + TODO).
- [x] Fix: reverted global `gradle.properties` setting; tried `tasks.withType<KotlinCompile>` in both `app/build.gradle.kts` and root `build.gradle.kts` `subprojects{}` (both failed — doesn't reach `:file_picker` subproject / doesn't work against Kotlin Build Tools API); final working fix is Windows-conditional `allprojects { extra.set("kotlin.incremental", "false") } ` in root `android/build.gradle.kts` (commit `37357cd`). Verified: `flutter clean && flutter pub get && flutter build apk --debug` succeeds, `flutter test` 42/42 pass, `flutter analyze` clean, real-device `integration_test/smoke_test.dart` passes. Docs corrected to match (`plan-issue-4.md`, commit `507c79b` on main, merged via `git merge main`).
- [ ] Next: `superpowers:finishing-a-development-branch` for this Issue 4 worktree.
