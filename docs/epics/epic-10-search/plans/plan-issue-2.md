# Epic 10 Issue 2ï¼šCBZï¼DRM KF8ï¼æœªä¸‹è??‡ç§»?¤å¿«?–æ›¸ç±ç?ç´¢å??€?‹è???Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** è®?Issue 1 ?„æ?ç¨‹å™¨æ­?¢ºè·³é??¬ä?å°±ä?è©²ç´¢å¼•ç??¸ç?ï¼ˆCBZï¼‰ï?ä¸¦è??Œæ–°?¸åŒ¯?¥ã€ã€Œé??°ä?è¼‰å??ã€ã€Œç§»?¤æœ¬æ©Ÿå¿«?–ã€ä??‹æ—¢?‰ä?ä»¶æ?ç¨‹æ­£ç¢ºé€??ç´¢å?è³‡æ??„å»ºç«?æ¸…é™¤/?šé?ï¼Œé¿?æ?ç¨‹å™¨æµªè²»è³‡æ??—è©¦ç´¢å?ä¸å??¨æ?ä¸æ”¯?´ç??§å®¹?ä??¿å?ä½¿ç”¨?…å·²?Ÿç”¨?¨æ?æª¢ç´¢å¾Œæ–°???æ–°ä¸‹è??„æ›¸æ°¸é?ä¸æ?è¢«ç´¢å¼•ã€?

**Architectureï¼?* ??`FullTextSearchSettingsRepository`ï¼ˆIssue 3 ?¢ç‰©ï¼‰æ–°å¢ä??‹å–®?¸ç?ç´šæ–¹æ³•ï?`markUnsupported`ï¼`handleBookAvailable`ï¼`clearBookIndex`ï¼‰ï?å»¶ç?è©²é??¥æ—¢?‰ã€Œç›´?¥å? `Database` ä¸?SQL ?ä? `content_index_status`/`book_content_index`?ç??¢å????ï¼›ä??‹æ—¢?‰ä?ä»¶è§¸?¼é?ï¼ˆ`_importSingleFile()` ?¯å…¥?¶æ?é»ã€é??°ä?è¼‰å??ã€ç§»?¤æœ¬æ©Ÿå¿«?–ï??„è‡ª?¼å«å°æ??¹æ?ï¼Œä??è?å¯¦ä? SQL?‚`handleBookAvailable()` ?¯å…¨?¨æ–°???æ–°ä¸‹è??±ç”¨?„å–®ä¸€?¥å£?”â€”ä??ªæ˜¯?Œé??°ä?è¼‰ã€å ´?¯å??¨ã€?

**Tech Stackï¼?* Flutter/Dart?`sqflite`ï¼ˆ`sqflite_common_ffi` ä¾›æ¸¬è©¦ï???

**Specï¼?* [`docs/epics/epic-10-search/spec.md`](../spec.md) Â§7ï¼ˆCBZï¼DRM KF8ï¼æœªä¸‹è??¸ç?ï¼Œæœ¬è¨ˆç•«?„å”¯ä¸€?€è¡“ä?å¯¦ä?æºï?ï¼›å·¥?®ä?æº?[`docs/epics/epic-10-search/issues.md`](../issues.md) Issue 2ï¼›`FullTextSearchSettingsRepository` ?¢æ?å¯¦ä? [`app/lib/search/full_text_search_settings_repository.dart`](../../../../app/lib/search/full_text_search_settings_repository.dart)ï¼ˆIssue 3 ?¢ç‰©ï¼Œæœ¬è¨ˆç•«å»¶ç??¶æ—¢?‰æ…£ä¾‹ï?ä¸é??°è¨­è¨ˆï???

## Global Constraints

- **?¬è??«å·²ç¶“é?ä¸€è¼ªè??«å¯©?¥ä¿®è¨?*ï¼ˆ`reviews/review-plan-issue-2.md`ï¼Œğ??Changes Requestedï¼? Criticalï¼? Importantï¼? Minorï¼‰ï?C-1ï¼ˆ`handleBookAvailable` ?ºæ??šé??’ç??¨ï??C-2ï¼ˆå?è¨ˆç•«?ªè???CBZï¼Œéºæ¼æ??‰æ–°?¯å…¥/ä¸‹è??¸ç??„ç´¢å¼•å?å¡«â€”â€?*?™æ˜¯?¬æ¬¡ä¿®è?å½±éŸ¿ç¯„å??€å¤§ç?ä¸€?…ï??Šæ–¹æ³•å??Œé??°ä?è¼‰å??¨ã€å?ç´šç‚º?Œæ??‰æ–°?¸å…±?¨ç??®ä??¥å£?ï?ä¸¦æ”¹??`handleDownloadCompleted` ??`handleBookAvailable` ?æ??™å€‹æ›´å»???„è???*ï¼‰ã€I-1ï¼ˆç¼ºå°?`isDownloaded` ?²ç¦¦æª¢æŸ¥ï¼‰ã€I-2ï¼ˆ`clearBookIndex` æ¸¬è©¦?ºæ?é©—è? `book_content_fts`ï¼‰ã€M-1ï¼ˆ`try/catch` ?²ç¦¦?§å?è£¹ï??M-2ï¼ˆ`didUpdateWidget` ?ªå?æ­?`_batchActions`ï¼‰å…¨?¸æŸ¥è­‰å±¬å¯¦ä¸¦?¡ç?ä¿®è?ï¼Œé€é?é«”ç¾?¨ä??¹å???Task ?§ã€‚åŸ·è¡Œè€…ä??€è¦å¦å¤–é?è®€å¯©æŸ¥?±å?ï¼Œæ??‰ä¿®è¨‚å·²?§å??ºå??‰ç?å¼ç¢¼?‡æ®µ?‡è??§è¨»è§?€?
- **ä¾è³´å·²æ»¿è¶?*ï¼šIssue 1?Issue 3 ?†å·²å®Œæ?ä¸¦å?ä½µï?`FullTextSearchSettingsRepository`ï¼`ContentIndexCategory`ï¼`SqliteFullTextSearchSettingsRepository` å·²å??¨ï??¬è??«åœ¨?¶ä??´å?ä¸‰å€‹æ–°?¹æ???
- **DRM KF8 æ¨™è???`unsupported`?”â€”æŸ¥è­‰å?ç¢ºè??¾è??¶æ?ä¸‹ç„¡äº‹å¯?šï??¬è??«åˆ»?ä?å¯¦ä?ä»»ä? DRM ?¸é?ç¨‹å?ç¢?*ï¼šæŸ¥è­?`app/lib/library/book_import_service_impl.dart:296-317`ï¼ˆazw3 ?†æ”¯ï¼‰ç™¼?¾ï??µæ¸¬??`DrmProtectedException` ?‚ç›®?æ˜¯ `return null`?”â€?*å®Œå…¨ä¸­æ­¢?¯å…¥ï¼Œé€?`Book` è¨˜é??½ä??ƒå»ºç«?*ï¼ˆè¨»è§??ç¢ºå??¨ã€Œspec.md?KF8 (AZW3) ?¯æ´?ã€ï??¯å¦ä¸€??Epic å·²è½?°ç??¢å?æ±ºç?ï¼Œé???Epic ç¯„å?ï¼‰ã€‚é€™ä»£è¡¨ç¾è¡Œæ¶æ§‹ä? DRM KF8 ?¸ç?æ°¸é?ä¸æ??ºç¾?¨å??¸åº«è£¡ï?ä¹Ÿå°±æ°¸é?ä¸æ???`content_index_status` ?—é?è¦æ?è¨˜ç‚º `unsupported`?”â€”epic-10-search spec.md Â§7 ?‡è¨­?ŒDRM KF8 ?¸ç??ƒè¢«?¯å…¥?åª?¯æ?è¨˜ç‚º unsupported?è??¾è??¯å…¥è¡Œç‚º?›ç›¾??*äººé?å·²æ???*ï¼šä?è¿½ç¿»?¢æ??¯å…¥?’ç?è¡Œç‚ºï¼ˆé‚£?¯å¦ä¸€??Epic ?„æ?ç¢ºæ±ºç­–ï??¹å?é¢¨éšª?‡ç??ç?è¶…å‡º?¬å·¥?®ï?ï¼Œæœ¬è¨ˆç•«?ªæ?ä»¶å??™å€‹è½å·®ï?ä¸å¯¦ä½œä»»ä½?DRM ?µæ¸¬/æ¨™è?ç¨‹å?ç¢¼ï??¥æœªä¾†æ???Epic æ±ºå??¹è? DRM KF8 ?„åŒ¯?¥æ?çµ•æ”¿ç­–ï?å±†æ??è??€è¦é??°è?ä¼°æ˜¯?¦è?æ¨™è? `unsupported`ï¼ˆ`FullTextSearchSettingsRepository.markUnsupported(bookId)`ï¼Œæœ¬è¨ˆç•« Task 1 ?¢å‡º?„æ–¹æ³•ï?å±†æ??¯ç›´?¥é??¨ï?ä¸é?è¦æ–°å¢ï???
- **`handleBookAvailable(Book book)` ?¯ã€Œæ–°?¸å…§å®¹é?æ¬¡å¯è¢«ç´¢å¼•ã€ç?çµ±ä?äº‹ä»¶ï¼Œæ¶µ?‹å…©ç¨®ç¾å­˜è§¸?¼æ?æ©Ÿï?review-plan-issue-2.md C-2 ä¿®è??é?ï¼?*ï¼?
  1. **ä»»ä??¼å??„æ–°?¸é?æ¬¡åŒ¯?¥å???*?”â€”`app/lib/library/book_import_service_impl.dart` ??`_importSingleFile()` ?¯å…¨å°ˆæ??€?‰æ–°?¸åŒ¯?¥è??²ç«¯/? ç«¯é¦–æ¬¡ä¸‹è???*?¯ä??¶æ?é»?*ï¼ˆæœ¬æ©Ÿæ?æ¡?è³‡æ?å¤¾é¸?–ã€Google Drive?OneDrive?Calibre/OPDS ?†ç???`BookImportService.importFiles()` ?¼å«?°é€™è£¡ï¼Œ`Book(...)` å»ºæ??‚å›ºå®?`isDownloaded: true`ï¼‰ã€?*?Ÿè??«ç¬¬ä¸€?ˆåª??CBZ ?†æ”¯?¼å« `markUnsupported()`ï¼Œå??¨éºæ¼å…¶é¤˜æ ¼å¼ï?EPUB/PDF/TXT/MDï¼‰â€”â€”é€™ä»£è¡¨ä½¿?¨è€…è‹¥å·²ç??¨è¨­å®šä¸­?Ÿç”¨?¨æ?æª¢ç´¢ï¼Œä?å¾ŒåŒ¯?¥ç?ä»»ä??°æ›¸?½ä??ƒæ? `content_index_status` ?—è¢«å»ºç?ï¼Œæ?ç¨‹å™¨æ°¸é?ä¸æ??¥é??‰é€™æœ¬?°æ›¸å­˜åœ¨ï¼Œå…¨?‡æª¢ç´¢æ°¸? æŸ¥ä¸åˆ°å®?*ï¼ˆå??ºç›®?å”¯ä¸€?ƒå»ºç«?`pending` ?—ç??°æ–¹??Issue 3 ??`setEnabled(true)`/`rebuildIndex()`ï¼Œåª?¨ä½¿?¨è€…å??›é???é»æ??å»º?¶ä??·è?ä¸€æ¬¡æ‰¹æ¬¡å?å¡«ï?ä¸æ??ç?????°æ›¸ï¼‰ã€‚æŸ¥è­‰å??¨ç¿»?Ÿè??«åˆ¤?·ï?`_importSingleFile()` ?’å…¥ `Book` è¨˜é?å¾Œæ”¹?ºçµ±ä¸€?¼å« `handleBookAvailable(insertedBook)`ï¼ˆä??åª??CBZ ?†æ”¯?¼å« `markUnsupported()`?”â€”CBZ ?„ç‰¹?¤é?è¼¯å??¨ç§»??`handleBookAvailable()` ?§éƒ¨ï¼Œ`book_import_service_impl.dart` ?¬èº«ä¸å??€è¦åˆ¤?·æ ¼å¼ï???
  2. **?¢æ? Calibre/OPDS ?¸ç??Œç§»?¤æœ¬æ©Ÿå¿«?–ã€å??ˆã€Œé??°ä?è¼‰ã€å???*?”â€”`app/lib/screens/library_screen.dart` ??`_handleRedownload()`ï¼Œé€™æ˜¯?¾è??¶æ?ä¸‹å”¯ä¸€?ƒç™¼?Ÿã€Œ`is_downloaded` å¾?0 è½‰ç‚º 1?ç??¢æ? code pathï¼ˆ`DownloadQueueController`ï¼`RemoteDownloadJob`ï¼`CloudDownloadJob` ?†å±¬?¼æ?å¢?1ï¼Œä?å¾‹èµ° `isDownloaded` å¾ä??‹å?å°±æ˜¯ `true` ?„æ–°?¯å…¥è·¯å?ï¼Œä?å±¬æ–¼?™å€‹æ?å¢ƒï???
- **`handleBookAvailable()` å¿…é??¼å« `_requestProcessing()`ï¼ˆreview-plan-issue-2.md C-1ï¼Œæ¨ç¿»å?è¨ˆç•«ç¬¬ä??ˆéºæ¼ï?**ï¼šå?è¨ˆç•«ç¬¬ä??ˆæ???`pending` ?—å?æ²’æ??šé??’ç??¨ï??¥æ?ç¨‹å™¨?¶ä??•æ–¼?’ç½®?€?‹ï?ä¾‹å??¸åº«?ˆå??„æ›¸ç±éƒ½å·²ç´¢å¼•å??¢ï?ï¼Œæ–°?¸æ??¡æ­»??`pending`ï¼Œç›´?°ä½¿?¨è€…æ°å¥½å???App ?å??°æ??‹é??±è??«é¢?æ?è¢«å?è§¸ç™¼?”â€”`content_indexing_scheduler.dart:85-93` ??`requestProcessing()` doc comment ?¬èº«å°±æ??‡å¯«?Œä??°æ›¸?¯å…¥?ä?è¼‰å??ï?Issue 2ï¼‰â€¦â€¦æ?ä¸»å??¼å«?ï?æ¯”ç…§ Issue 3 `setEnabled(true)`/`rebuildIndex()` ?’å…¥ `pending` å¾Œå‘¼??`_requestProcessing()` ?„æ—¢?‰æ…£ä¾‹ã€?
- **`handleBookAvailable()` å¿…é?æª¢æŸ¥ `book.isDownloaded`ï¼ˆreview-plan-issue-2.md I-1ï¼?*ï¼š`if (!book.isDownloaded) return;` ä½œç‚º?¹æ??‹é ­?„ç¬¬ä¸€?“é˜²ç·šï???spec.md Â§7?Œæœªä¸‹è??¸ç?ä¸å»ºç«?content_index_status ?—ã€é€™å€‹ä?è®Šé??¶æ??²æ–¹æ³•æœ¬èº«ã€ä?ä¾è³´æ¯å€‹å‘¼?«ç«¯?ªè??µå??‚æœ¬è¨ˆç•«?®å??©å€‹å‘¼?«ç«¯ï¼ˆ`_importSingleFile()`ï¼`_handleRedownload()`ï¼‰åœ¨?¼å«?¶ä??½å·²ç¶“ç¢ºä¿?`isDownloaded == true`ï¼Œé€™é?æª¢æŸ¥?¯é¢?‘æœªä¾†å‘¼?«ç«¯?„é˜²ç¦¦æ€§è¨­è¨ˆã€?
- **`markUnsupported()`ï¼`handleBookAvailable()` ??INSERT ?†æ¡??`ConflictAlgorithm.ignore`**ï¼šå·²?‰è??™å??„æ›¸ç±ä?å¾‹ä?è¦†è?ï¼Œæ???Issue 3 `_backfillPending()` ?¢æ??„ã€Œå·²?‰è??™å??„æ›¸ç±ä?å¾‹è·³?ã€å??‡ã€?
- **CBZ ??`handleBookAvailable()` ?§ç??¹æ??•ç?**ï¼šä???Calibre/OPDS ä¾†æ???CBZ ?¸ç??†è?ä¸Šä??¯èƒ½è¢«ç§»?¤å¿«?–å??ˆé??°ä?è¼‰â€”â€”`clearBookIndex()` ?ƒæ?å®ƒç? `unsupported` ?—ä?ä½µæ??‰ï?æ­¤æ? `handleBookAvailable()` å¿…é??æ–°?Šå?æ¨™è???`unsupported`ï¼ˆè€Œä??¯ç•¥?æ?èª¤åˆ¤?èµ°ä¸€??`pending` æµç?ï¼‰ï?? æ­¤?§éƒ¨?è¼¯?¯ã€ŒCBZ ä¸€å¾‹å‘¼??`markUnsupported()`ï¼Œå…¶é¤˜æ ¼å¼æ?æª¢æŸ¥ `isEnabled(category)` æ±ºå??¯å¦?’å…¥ `pending`?ï?ä¸æ˜¯ spec.md Â§7 ?å??è¿°?„å?å§‹ç??¬ï?è©²æ®µ?½åª?è¿°äº†é? CBZ ?…å?ï¼‰ï??¬è??«è??ºå??¢æ?è¦å??„å?è¦å»¶ä¼¸ï??†ç”±å¦‚ä???
- **`clearBookIndex()` æ¸¬è©¦å¿…é?é©—è? `book_content_fts` ?Œæ­¥æ¸…ç©ºï¼ˆreview-plan-issue-2.md I-2ï¼?*ï¼šæ???Issue 3 ?¢æ? `setEnabled(pdf, false)` æ¸¬è©¦??`db.rawQuery("SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH ...")` ?¢æ??·è??‹æ?ï¼Œ`issues.md` Issue 2 ?®å?æ¸¬è©¦è¦æ??å??—å‡º?Œ`book_content_index`/`content_index_status`/`book_content_fts` è³‡æ??—ç?æ¸…ç©º?ä?å¼µè¡¨ï¼Œç¼ºä¸€ä¸å¯??
- **?œå?ç´¢å??¯è??Ÿæ€§è??™ï??¶å¯«??æ¸…é™¤å¤±æ?ä¸æ??»æ–·?–èª¤?¤ä¸»æµç?å¤±æ?ï¼ˆreview-plan-issue-2.md M-1ï¼?*ï¼šæ???`library_batch_actions.dart` ?¢æ??Œæ?æ¡ˆåˆª?¤å¤±?—æ??œé??¥é??”â€”è??™åº«æ¨™è??´æ–°?æ˜¯?¸å??ä??ç??¢å????ï¼Œ`_importSingleFile()`ï¼`_handleRedownload()`ï¼`removeLocalCache()` ?¼å« `handleBookAvailable()`/`clearBookIndex()` ä¸€å¾‹å???`try/catch` ?§é?é»˜ç•¥?ä?å¤–ï?ä¸è?ç´¢å?ç¶­è­·?„å¤±?—é€?¸¶è®“ä½¿?¨è€…ç??°ã€ŒåŒ¯?¥å¤±?—ã€??Œé??°ä?è¼‰å¤±?—ã€ï?ä¹Ÿä?è®“æ‰¹æ¬¡ç§»?¤å¿«?–è¿´?ˆå??®ä??¸ç??„ç´¢å¼•æ??¤ç•°å¸¸è€Œä¸­?·å?çºŒæ›¸ç±ã€?
- **`LibraryScreen.didUpdateWidget()` ?€?Œæ­¥?´æ–° `_batchActions`ï¼ˆreview-plan-issue-2.md M-2ï¼?*ï¼š`_batchActions` ??`initState()` å»ºæ??‚æ??‰ä??¶ä???`repository`/`fullTextSearchSettingsRepository` ?ƒè€ƒï??¥ä?å±?`readerFeatureRepositories`ï¼`repository` ä¹‹å?è¢«æ›¿?›ï?ä¾‹å?æ¸¬è©¦?…å?ï¼‰ï??€è¦åœ¨ `didUpdateWidget()` ?æ–°å»ºæ?ï¼Œé¿?ç¹¼çºŒæ??‰é??Ÿå??ƒã€?
- ä¸ä¿®??`ContentIndexingScheduler`ï¼ˆIssue 1ï¼Issue 3 å·²å??ï?ä¸æ??¥æœ¬å·¥å–®?°å??„ä??‹æ–¹æ³•ï?ç´”ç²¹?¯æ?è²»æ—¢??`content_index_status` ä½‡å?ï¼‰ã€?
- ä¸æ–°å¢?DB migrationï¼Œ`content_index_status`/`book_content_index` schema æ²¿ç”¨ Issue 0 ?¢æ??ˆæœ¬ï¼ˆ`version: 24`ï¼‰ä?è®Šã€?
- ?€?‰æ–°å¢ç?å¼ç¢¼è¨»è§£ä½¿ç”¨æ­??ä¸­æ?ï¼ˆzh-TWï¼‰ï?æ¯”ç…§?¨å?æ¡ˆæ—¢?‰æ…£ä¾‹ã€?

---

## æª”æ?çµæ?ç¸½è¦½

- **Modifyï¼?* `app/lib/search/full_text_search_settings_repository.dart` ???½è±¡ä»‹é¢?‡å¯¦ä½œæ–°å¢?`markUnsupported`ï¼`handleBookAvailable`ï¼`clearBookIndex` ä¸‰å€‹æ–¹æ³•ã€?
- **Modifyï¼?* `app/test/search/full_text_search_settings_repository_test.dart`
- **Modifyï¼?* `app/test/support/fake_full_text_search_settings_repository.dart` ???°å?ä¸‰å€‹æ–¹æ³•ç??‡å¯¦ä½œï??¼å«è¨˜é?æ¸…å–®??
- **Modifyï¼?* `app/lib/library/book_import_service_impl.dart` ??å»ºæ?å­æ–°å¢å¯??`fullTextSearchSettingsRepository`ï¼›`_importSingleFile()` çµ±ä??¼å« `handleBookAvailable()`ï¼ˆä???CBZï¼‰ã€?
- **Modifyï¼?* `app/test/library/book_import_service_test.dart`
- **Modifyï¼?* `app/lib/screens/library_screen.dart` ??`_handleRedownload()` å®Œæ?å¾Œå‘¼??`handleBookAvailable()`ï¼›`didUpdateWidget()` ?Œæ­¥ `_batchActions`??
- **Modifyï¼?* `app/test/screens/library_screen_test.dart`
- **Modifyï¼?* `app/lib/screens/library_batch_actions.dart` ??å»ºæ?å­æ–°å¢å¯??`fullTextSearchSettingsRepository`ï¼›`removeLocalCache()` ?¼å« `clearBookIndex()`??
- **Modifyï¼?* `app/test/screens/library_batch_actions_test.dart`
- **Modifyï¼?* `app/lib/main.dart` ???æ–°?’å?å»ºæ??†å?ï¼Œè? `fullTextSearchSettingsRepository` ??`importService` ä¹‹å?å°±ç?ï¼Œä¸¦?³å…¥ `BookImportServiceImpl`??

---

### Task 1ï¼š`FullTextSearchSettingsRepository` ?°å??®æ›¸ç­‰ç??¹æ?

**Filesï¼?*
- Modify: `app/lib/search/full_text_search_settings_repository.dart`
- Modify: `app/test/support/fake_full_text_search_settings_repository.dart`
- Test: `app/test/search/full_text_search_settings_repository_test.dart`

**Interfacesï¼?*
- Consumesï¼šæ—¢??`SqliteFullTextSearchSettingsRepository` ??`_database`ï¼`isEnabled()`ï¼`_requestProcessing` ç­‰æ—¢?‰ç??‰æ??¡è??¹æ???
- Producesï¼š`FullTextSearchSettingsRepository` ?°å? `Future<void> markUnsupported(String bookId)`ï¼`Future<void> handleBookAvailable(Book book)`ï¼`Future<void> clearBookIndex(String bookId)` ä¸‰å€‹æ–¹æ³•â€”â€”ä? Task 2ï¼?ï¼? ?¼å«?‚`FakeFullTextSearchSettingsRepository` ?°å?å°æ???`markUnsupportedCalls`ï¼`handleBookAvailableCalls`ï¼`clearBookIndexCalls` è¨˜é?æ¸…å–®?”â€”ä? Task 3ï¼? ??widget/unit test ?·è?ä½¿ç”¨??

- [x] **Step 1ï¼šå¯«ä¸€çµ„æ?å¤±æ?ï¼ˆç·¨è­¯éŒ¯èª¤ï??„æ¸¬è©?*

??`app/test/search/full_text_search_settings_repository_test.dart`ï¼Œæ‰¾?°æ—¢??`group('epic-10-search Issue 3ï¼šFullTextSearchSettingsRepository', () { ... });` ?€å¡Šå…§?€å¾Œä??‹æ¸¬è©¦ï?`rebuildIndex(category)` ???ï¼‰ä?å¾Œã€å?å¡Šæ”¶å°?`});` ä¹‹å?ï¼Œæ–°å¢ï?

```dart
    test('markUnsupported() å¯«å…¥ unsupported ?€?‹ï?epic-10-search Issue 2ï¼?,
        () async {
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await repository.markUnsupported('cbz-1');

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
    });

    test('markUnsupported() ä¸è??‹å·²å­˜åœ¨?„è??™å?', () async {
      await libraryRepository.insertBook(_book('book-1'));
      await db.insert('content_index_status',
          {'book_id': 'book-1', 'status': 'done', 'updated_at': 1000});

      await repository.markUnsupported('book-1');

      final status = await statusOf('book-1');
      expect(status!['status'], 'done');
    });

    test(
        'handleBookAvailable() å°?CBZ ?¸ç?ä¸€å¾‹æ?è¨?unsupportedï¼Œä??¼å« requestProcessing',
        () async {
      final book = _book('cbz-1', format: BookFileFormat.cbz);
      await libraryRepository.insertBook(book);

      await repository.handleBookAvailable(book);

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
      expect(requestProcessingCallCount, 0);
    });

    test(
        'handleBookAvailable() ä¾æ ¼å¼å??‰å?é¡æ˜¯?¦å??¨æ±ºå®šæ˜¯?¦æ???pendingï¼?
        '?’å…¥?‚å??’æ?ç¨‹å™¨ï¼ˆreview-plan-issue-2.md C-1ï¼?, () async {
      final pdfBook = _book('pdf-1', format: BookFileFormat.pdf);
      final epubBook = _book('epub-1');
      await libraryRepository.insertBook(pdfBook);
      await libraryRepository.insertBook(epubBook);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      // setEnabled(true) ?¬èº«?„æ‰¹æ¬¡å?å¡«ä??ƒå‘¼?«ä?æ¬?requestProcessingï¼?
      // ?ç½®è¨ˆæ•¸?ªé?è­?handleBookAvailable() ?™ä?æ­¥ç?è¡Œç‚º??
      requestProcessingCallCount = 0;

      await repository.handleBookAvailable(pdfBook);
      await repository.handleBookAvailable(epubBook);

      final pdfStatus = await statusOf('pdf-1');
      expect(pdfStatus, isNotNull);
      expect(pdfStatus!['status'], 'pending');
      // foliate ?†é??ªå??¨ï?epub-1 ä¸æ?è¢«æ??¥ä»»ä½•è??™å???
      expect(await statusOf('epub-1'), isNull);
      // ?ªæ? pdf-1 ?Ÿç??’å…¥ pendingï¼Œåª?šé??’ç??¨ä?æ¬¡ã€?
      expect(requestProcessingCallCount, 1);
    });

    test('handleBookAvailable() ä¸è??‹å·²å­˜åœ¨?„è??™å?', () async {
      final book = _book('pdf-1', format: BookFileFormat.pdf);
      await libraryRepository.insertBook(book);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      await db.update('content_index_status', {'status': 'done'},
          where: 'book_id = ?', whereArgs: ['pdf-1']);

      await repository.handleBookAvailable(book);

      final status = await statusOf('pdf-1');
      expect(status!['status'], 'done');
    });

    test(
        'handleBookAvailable() å°?isDownloaded == false ?„æ›¸ç±ä??šä»»ä½•ä?'
        'ï¼ˆreview-plan-issue-2.md I-1ï¼?, () async {
      final book = _book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      );
      await libraryRepository.insertBook(book);
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      requestProcessingCallCount = 0;

      await repository.handleBookAvailable(book);

      expect(await statusOf('pdf-not-downloaded'), isNull);
      expect(requestProcessingCallCount, 0);
    });

    test(
        'clearBookIndex() æ¸…é™¤?®ä??¸ç??„ç´¢å¼•è??™ï???book_content_ftsï¼‰ï?'
        'ä¸å½±?¿å…¶ä»–æ›¸ç±ï?review-plan-issue-2.md I-2ï¼?, () async {
      await libraryRepository.insertBook(_book('book-1'));
      await libraryRepository.insertBook(_book('book-2'));
      await db.insert('content_index_status',
          {'book_id': 'book-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'book-2', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-1',
        'book_id': 'book-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': '?¸ä??§å®¹',
        'token_text': '?¸ä??§å®¹',
        'created_at': 1000,
      });
      await db.insert('book_content_index', {
        'id': 'seg-2',
        'book_id': 'book-2',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': '?¸ä??§å®¹',
        'token_text': '?¸ä??§å®¹',
        'created_at': 1000,
      });

      await repository.clearBookIndex('book-1');

      expect(await statusOf('book-1'), isNull);
      expect(await statusOf('book-2'), isNotNull);
      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRows, isEmpty);
      final ftsRowsBook1 = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '?¸ä?'");
      expect(ftsRowsBook1, isEmpty,
          reason: 'FTS5 trigger ?‰å?æ­¥æ?ç©ºå·²?ªé™¤??book-1 ç´¢å???);
      final ftsRowsBook2 = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '?¸ä?'");
      expect(ftsRowsBook2, isNotEmpty,
          reason: 'book-2 ?„ç´¢å¼•ä??‰å? book-1 ??clearBookIndex å½±éŸ¿');
    });
```

- [x] **Step 2ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè?? ç‚º production API å°šä?å­˜åœ¨?Œç·¨è­¯å¤±??*

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: FAILï¼ˆç·¨è­¯éŒ¯èª¤ï?`FullTextSearchSettingsRepository`ï¼`SqliteFullTextSearchSettingsRepository` æ²’æ? `markUnsupported`/`handleBookAvailable`/`clearBookIndex` ?¹æ?ï¼‰ã€?

- [x] **Step 3ï¼šå¯¦ä½œä??‹æ–°?¹æ?**

??`app/lib/search/full_text_search_settings_repository.dart`ï¼Œæ–¼æª”æ??‚ç«¯ import ?€å¡Šæ–°å¢ï?

```dart
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
```

?¾åˆ°ï¼?

```dart
abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
  Future<void> rebuildIndex(ContentIndexCategory category);
}
```

?–ä»£?ºï?

```dart
abstract class FullTextSearchSettingsRepository {
  Future<bool> isEnabled(ContentIndexCategory category);
  Future<void> setEnabled(ContentIndexCategory category, bool value);
  Future<void> rebuildIndex(ContentIndexCategory category);

  /// ??[bookId] æ¨™è???`content_index_status.status = 'unsupported'`
  /// ï¼ˆepic-10-search Issue 2ï¼Œè? spec.md Â§7ï¼‰ï?CBZ ?¯å…¥?¶ä??¼å«ï¼Œå¤©?Ÿè¢«
  /// ?’ç??¨ç? pending ?¥è©¢?’é™¤ï¼ˆ`status != 'pending'/'indexing'`ï¼‰ã€‚å·²??
  /// è³‡æ??—æ?ä¸è??‹ã€?
  Future<void> markUnsupported(String bookId);

  /// [book] ?›è??æœ¬æ©Ÿå¯?¨ï?é¦–æ¬¡?¯å…¥å®Œæ?ï¼Œæ??¢æ??¸ç??æ–°ä¸‹è?å®Œæ?ï¼‰æ?
  /// ?¼å«ï¼ˆepic-10-search Issue 2ï¼Œè? spec.md Â§7ï¼‰ï?CBZ ä¸€å¾‹æ?è¨?
  /// `unsupported`ï¼›å…¶é¤˜æ ¼å¼ä? `book.format` å°æ???[ContentIndexCategory]
  /// ?¯å¦å·²å??¨ï?å·²å??¨æ?è£œæ??¥ä?ç­?`status='pending'` ä¸¦å??’æ?ç¨‹å™¨ï¼Œæœª
  /// ?Ÿç”¨?‡ä??’å…¥?‚`book.isDownloaded` å¿…é???`true`?”â€”`false` ?‚ç›´?¥ä???
  /// ä»»ä?äº‹ï?spec.md Â§7ï¼šæœªä¸‹è??¸ç?ä¸å»ºç«?`content_index_status` ?—ï?ï¼?
  /// ?¼å«ç«¯ä??€è¦è‡ªè¡Œæª¢?¥ï?review-plan-issue-2.md I-1ï¼‰ã€‚å·²?‰è??™å???
  /// ä¸è??‹ã€?
  Future<void> handleBookAvailable(Book book);

  /// ç§»é™¤ [bookId] ?¬æ?å¿«å?ï¼ˆ`is_downloaded` è½‰å? 0ï¼‰æ??¼å«ï¼ˆepic-10-search
  /// Issue 2ï¼Œè? spec.md Â§7ï¼‰ï?æ¸…é™¤è©²æ›¸??`book_content_index`ï¼?
  /// `content_index_status` è³‡æ??—ï?æ¯”ç…§?Œé?å»ºç´¢å¼•ã€å?ä¸€æ®µæ??¤é?è¼¯ä???
  /// ?å??®ä??¸ç???
  Future<void> clearBookIndex(String bookId);
}
```

?¾åˆ° `SqliteFullTextSearchSettingsRepository` é¡åˆ¥?§ç? `rebuildIndex()` ?¹æ?ï¼?

```dart
  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _clearIndexData(category);
    await _backfillPending(category);
    _requestProcessing();
  }
```

?¨å…¶å¾Œï?`_backfillPending()` ?¹æ?å®šç¾©ä¹‹å?ï¼‰æ??¥ä??‹æ–°?¹æ?ï¼?

```dart
  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    await _clearIndexData(category);
    await _backfillPending(category);
    _requestProcessing();
  }

  @override
  Future<void> markUnsupported(String bookId) async {
    await _database.insert(
      'content_index_status',
      {
        'book_id': bookId,
        'status': 'unsupported',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    // ?review-plan-issue-2.md I-1?‘æ? spec.md Â§7 ?„ä?è®Šé??¶æ??²æ–¹æ³•æœ¬èº«ï?
    // ä¸ä?è³´æ??‹å‘¼?«ç«¯?ªè?æª¢æŸ¥??
    if (!book.isDownloaded) return;
    if (book.format == BookFileFormat.cbz) {
      // ?è??ƒé?æ®µæŸ¥è­‰ã€‘ä???Calibre/OPDS ä¾†æ???CBZ ?¸ç??¯èƒ½? ç§»?¤å¿«??
      // ?Œå?è¢?clearBookIndex() æ¸…æ??¢æ???unsupported ?—ï??æ–°ä¸‹è?å®Œæ?
      // ?‚å??ˆé??°æ?è¨˜å? unsupportedï¼Œä??¯èª¤?¤æ?èµ°ä???pending æµç???
      await markUnsupported(book.id);
      return;
    }
    final category = book.format == BookFileFormat.pdf
        ? ContentIndexCategory.pdf
        : ContentIndexCategory.foliate;
    if (!await isEnabled(category)) return;
    await _database.insert(
      'content_index_status',
      {
        'book_id': book.id,
        'status': 'pending',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // ?review-plan-issue-2.md C-1?‘éºæ¼é€™è??ƒè??°æ›¸?¡æ­»??pendingï¼Œç›´??
    // ä½¿ç”¨?…æ°å¥½å???App ?å??°æ??‹é??±è??«é¢?æ?è¢«å??šé??”â€”æ??§æ—¢??
    // setEnabled(true)/rebuildIndex() ?¢æ????ï¼Œæ???pending å¾Œå??ˆä¸»??
    // ?šé??’ç??¨ã€?
    _requestProcessing();
  }

  @override
  Future<void> clearBookIndex(String bookId) async {
    await _database.transaction((txn) async {
      await txn.delete('book_content_index',
          where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete('content_index_status',
          where: 'book_id = ?', whereArgs: [bookId]);
    });
  }

```

??`app/test/support/fake_full_text_search_settings_repository.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import 'package:elinkbook/library/models/book.dart';
```

?¾åˆ°ï¼?

```dart
  /// è¨˜é?æ¯æ¬¡ [rebuildIndex] ?¼å«??`category`ï¼ˆreview-plan-issue-3.md
  /// I-1ï¼‰ã€?
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }
}
```

?–ä»£?ºï?

```dart
  /// è¨˜é?æ¯æ¬¡ [rebuildIndex] ?¼å«??`category`ï¼ˆreview-plan-issue-3.md
  /// I-1ï¼‰ã€?
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  /// è¨˜é?æ¯æ¬¡ [markUnsupported]ï¼[handleBookAvailable]ï¼[clearBookIndex]
  /// ?¼å«ï¼ˆepic-10-search Issue 2ï¼‰ã€?
  final List<String> markUnsupportedCalls = [];
  final List<Book> handleBookAvailableCalls = [];
  final List<String> clearBookIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }

  @override
  Future<void> markUnsupported(String bookId) async {
    markUnsupportedCalls.add(bookId);
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    handleBookAvailableCalls.add(book);
  }

  @override
  Future<void> clearBookIndex(String bookId) async {
    clearBookIndexCalls.add(bookId);
  }
}
```

- [x] **Step 4ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè??šé?**

Run: `flutter test test/search/full_text_search_settings_repository_test.dart`
Expected: PASSï¼?8 ?…æ¸¬è©¦å…¨?ï??¢æ? 11 ?…ï??¬æ¬¡?°å? 7 ?…ï???

- [x] **Step 5ï¼š`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6ï¼šCommit**

```bash
git add app/lib/search/full_text_search_settings_repository.dart app/test/support/fake_full_text_search_settings_repository.dart app/test/search/full_text_search_settings_repository_test.dart
git commit -m "feat(search): FullTextSearchSettingsRepository ?°å??®æ›¸ç´¢å??€?‹æ–¹æ³•ï?Issue 2ï¼?
```

---

### Task 2ï¼šæ–°?¯å…¥?¸ç?çµ±ä?????¨æ?æª¢ç´¢ç´¢å??€??

**Filesï¼?*
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfacesï¼?*
- Consumesï¼šTask 1 ??`FullTextSearchSettingsRepository.handleBookAvailable(Book book)`??
- Producesï¼š`BookImportServiceImpl` å»ºæ?å­æ–°å¢å¯?¸å…·?å???`FullTextSearchSettingsRepository? fullTextSearchSettingsRepository`ï¼ˆ`null` ?‚è??ºè??¾è?å®Œå…¨ä¸€?´ï?ä¸å¯«?¥ä»»ä½?`content_index_status` ?—ï??”â€”ä? Task 5ï¼ˆ`main.dart`ï¼‰æ³¨?¥æ­£å¼å¯¦ä¾‹ã€?

- [x] **Step 1ï¼šå¯«ä¸€çµ„æ?å¤±æ??„æ¸¬è©?*

??`app/test/library/book_import_service_test.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
```

??`group('CBZ ?¯å…¥', () { ... });` ?€å¡Šå…§ï¼Œæ‰¾?°æ?å¾Œä??‹æ—¢?‰æ¸¬è©¦ï?`contentFingerprint å°å?å§?content:// URI è¨ˆç?...`ï¼‰ç?å°¾è??€å¡Šæ”¶å°?`});` ä¹‹é?ï¼ˆ`makeValidCbz()`ï¼`makeEmptyCbz()` ?™å…©?‹å?å¡Šå…§?½å??¨æ­¤ç¯„å??§ä??¨ä??¨å?ä¸­ï?ï¼Œæ–°å¢ï?

```dart
    test(
        'CBZ ?¯å…¥?å?å¾Œï?content_index_status æ¨™è???unsupported'
        'ï¼ˆepic-10-search Issue 2ï¼?, () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/unsupported_comics.cbz'],
        displayNames: ['unsupported_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'unsupported');
    });

    test(
        '?ªæ?ä¾?fullTextSearchSettingsRepositoryï¼ˆnullï¼‰æ?ï¼ŒCBZ ?¯å…¥çµæ?ä¸å?å½±éŸ¿ï¼?
        'ä¹Ÿä?å¯«å…¥ content_index_status', () async {
      final cbzBytes = makeValidCbz();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final args = call.arguments as Map;
          await File(args['destinationPath'] as String)
              .writeAsBytes(cbzBytes);
          return null;
        }
        return null;
      });

      final result = await service.importFiles(
        ['content://example/no_search_comics.cbz'],
        displayNames: ['no_search_comics.cbz'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
```

?¨å?ä¸€?‹æ?æ¡ˆå…§ï¼Œ`main()` ?§ä»»ä¸€ä½ç½®ï¼ˆä?å¦‚ç??¥åœ¨ `group('CBZ ?¯å…¥', ...)` ?€å¡Šä?å¾Œï??°å?ä¸€?‹æ–°??`group`ï¼Œæ¶µ??CBZ ä»¥å??¼å??„é€??ï¼?*review-plan-issue-2.md C-2**ï¼šé?è­‰å?è¨ˆç•«ç¬¬ä??ˆéºæ¼ç??Œä??¬æ ¼å¼æ–°?¸åŒ¯?¥ã€æ?å¢ƒï?ï¼?

```dart
  group('epic-10-search Issue 2ï¼šæ–°?¯å…¥?¸ç??¨æ?æª¢ç´¢?€?‹é€??ï¼ˆé? CBZ ?¼å?ï¼?, () {
    test('EPUB ?¯å…¥?‚è‹¥ foliate ?†é?å·²å??¨ï?å¯«å…¥ pending ä¸¦å??’æ?ç¨‹å™¨',
        () async {
      var requestProcessingCallCount = 0;
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () => requestProcessingCallCount++,
      );
      await fullTextSearchSettingsRepository.setEnabled(
        ContentIndexCategory.foliate,
        true,
      );
      // setEnabled(true) ?¬èº«?„æ‰¹æ¬¡å?å¡«ä??ƒå‘¼?«ä?æ¬¡ï??ç½®è¨ˆæ•¸?ªé?è­‰åŒ¯??
      // ?™ä?æ­¥è§¸?¼ç??šé?æ¬¡æ•¸??
      requestProcessingCallCount = 0;
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': 'æ¸¬è©¦??};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'pending');
      expect(requestProcessingCallCount, 1);
    });

    test('EPUB ?¯å…¥?‚è‹¥ foliate ?†é??ªå??¨ï?ä¸å¯«??content_index_status',
        () async {
      final fullTextSearchSettingsRepository =
          SqliteFullTextSearchSettingsRepository(
        database: repository.database,
        requestProcessing: () {},
      );
      final serviceWithSearch = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
      );
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'extractMetadata') {
          return {'title': 'æ¸¬è©¦??};
        }
        return null;
      });

      final result = await serviceWithSearch.importFiles(
        ['content://example/new_book_disabled.epub'],
      );

      expect(result.importedBooks, hasLength(1));
      final rows = await repository.database.query(
        'content_index_status',
        where: 'book_id = ?',
        whereArgs: [result.importedBooks.first.id],
      );
      expect(rows, isEmpty);
    });
  });
```

- [x] **Step 2ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè?? ç‚º production API å°šä?å­˜åœ¨?Œç·¨è­¯å¤±??*

Run: `flutter test test/library/book_import_service_test.dart`
Expected: FAILï¼ˆç·¨è­¯éŒ¯èª¤ï?`BookImportServiceImpl` æ²’æ? `fullTextSearchSettingsRepository` ?·å??ƒæ•¸ï¼‰ã€?

- [x] **Step 3ï¼šå¯¦ä½?*

??`app/lib/library/book_import_service_impl.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import '../search/full_text_search_settings_repository.dart';
```

?¾åˆ°ï¼?

```dart
class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    AppThemePreferences? themePreferences,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences();

  // ä½¿ç”¨ kBookMetadataChannelï¼ˆlibrary_repository.dartï¼‰ä??ºå…±?¨é€šé??ç¨±??

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final AppThemePreferences _themePreferences;
```

?–ä»£?ºï?

```dart
class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    AppThemePreferences? themePreferences,
    FullTextSearchSettingsRepository? fullTextSearchSettingsRepository,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences(),
        _fullTextSearchSettingsRepository = fullTextSearchSettingsRepository;

  // ä½¿ç”¨ kBookMetadataChannelï¼ˆlibrary_repository.dartï¼‰ä??ºå…±?¨é€šé??ç¨±??

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final AppThemePreferences _themePreferences;

  /// epic-10-search Issue 2ï¼ˆspec.md Â§7ï¼‰ï??°æ›¸?¯å…¥?å?å¾Œé€???¨æ?æª¢ç´¢
  /// ç´¢å??€?‹ï?CBZ æ¨™è? unsupportedï¼›å…¶é¤˜æ ¼å¼ä??‹é??€?‹æ±ºå®šæ˜¯?¦æ???
  /// pendingï¼‰ã€‚`null` ?‚ï?ä¾‹å??¢æ?æ¸¬è©¦?ªæ?ä¾›ï?å®Œå…¨?¥é?ï¼Œè??ºè??¬å·¥??
  /// ä¹‹å?å®Œå…¨ä¸€?´ã€?
  final FullTextSearchSettingsRepository? _fullTextSearchSettingsRepository;
```

?¾åˆ° `_importSingleFile()` ?¹æ?çµå°¾ï¼?

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: source,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      // ?è¨º?·ä¿®æ­??epic-18-reader-device-qa Issue 29?‘å??¯å…¥?å??ªæ??‹é?
      // ?„æ›¸ä¸è©²è¦–ç‚º?Œå?è®€?ã€â€”â€”ç”¨ epoch 0 è¡¨ç¤º?Œå??ªè??ã€ç??¨å…µ?¼ï?
      // è®“ã€Œæ?å¾Œé–±è®€?æ?åºï??ªå??‹æ›¸æ°¸é??Šå??’åœ¨ä»»ä??Ÿæ­£è¢«è??ç??¸ä?å¾Œã€?
      // `lastReadTime` æ¬„ä???`NOT NULL`ï¼Œæ”¹??nullable ?€è¦?schema
      // migrationï¼Œç”¨?¨å…µ?¼æ??°å??¯ç‚º null ?„æ?ä½æ”¹?•ç??æ›´å°ã€‚ç?æ­??
      // ?Œæ?å¾Œé–±è®€?‚é??ç”± ReadingPositionRepository.save() ?¼ä½¿?¨è€…å¯¦??
      // ?±è??ä?ç½®æ??°å??‚çµ±ä¸€ç¶­è­·??
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    return _repository.insertBook(book);
  }
```

?–ä»£?ºï?

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: bookFilePath,
      source: source,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      contentFingerprint: contentFingerprint,
      remoteServerId: remoteServerId,
      remoteBookId: remoteBookId,
      remoteDownloadUrl: remoteDownloadUrl,
      isDownloaded: true,
      cloudFileId: cloudFileId,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      // ?è¨º?·ä¿®æ­??epic-18-reader-device-qa Issue 29?‘å??¯å…¥?å??ªæ??‹é?
      // ?„æ›¸ä¸è©²è¦–ç‚º?Œå?è®€?ã€â€”â€”ç”¨ epoch 0 è¡¨ç¤º?Œå??ªè??ã€ç??¨å…µ?¼ï?
      // è®“ã€Œæ?å¾Œé–±è®€?æ?åºï??ªå??‹æ›¸æ°¸é??Šå??’åœ¨ä»»ä??Ÿæ­£è¢«è??ç??¸ä?å¾Œã€?
      // `lastReadTime` æ¬„ä???`NOT NULL`ï¼Œæ”¹??nullable ?€è¦?schema
      // migrationï¼Œç”¨?¨å…µ?¼æ??°å??¯ç‚º null ?„æ?ä½æ”¹?•ç??æ›´å°ã€‚ç?æ­??
      // ?Œæ?å¾Œé–±è®€?‚é??ç”± ReadingPositionRepository.save() ?¼ä½¿?¨è€…å¯¦??
      // ?±è??ä?ç½®æ??°å??‚çµ±ä¸€ç¶­è­·??
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final insertedBook = await _repository.insertBook(book);
    // epic-10-search Issue 2ï¼ˆspec.md Â§7ï¼Œreview-plan-issue-2.md C-2ï¼‰ï?
    // _importSingleFile() ?¯å…¨å°ˆæ??€?‰æ–°?¸åŒ¯?¥è??²ç«¯/? ç«¯é¦–æ¬¡ä¸‹è??„å”¯ä¸€
    // ?¶æ?é»ï??¬æ?æª”æ?/è³‡æ?å¤¾é¸?–ã€Google Drive?OneDrive?Calibre/OPDS
    // ?†ç???BookImportService.importFiles() ?¼å«?°é€™è£¡ï¼‰ã€‚çµ±ä¸€?¼å«
    // handleBookAvailable()ï¼ˆä???CBZï¼‰è??€?‰æ ¼å¼éƒ½?½åœ¨å·²å??¨å…¨?‡æª¢ç´¢ç?
    // ?…æ?ä¸‹æ­£ç¢ºè¢«?’å…¥ pending ä½‡å?ä¸¦å??’æ?ç¨‹å™¨?‚search-index ?ªæ˜¯è¡ç?
    // è³‡æ?ï¼Œå¯«?¥å¤±?—ä??‰è??Ÿæœ¬å·²æ??Ÿç??¸ç??¯å…¥è¢«åˆ¤å®šå¤±??
    // ï¼ˆreview-plan-issue-2.md M-1ï¼‰ã€?
    try {
      await _fullTextSearchSettingsRepository?.handleBookAvailable(
        insertedBook,
      );
    } catch (_) {
      // ?œé??¥é??”â€”æ›¸ç±è??„å·²?å?å»ºç?ï¼Œå…¨?‡æª¢ç´¢ç´¢å¼•ç??‹å¯?¥å??é?
      // ?Œé?å»ºç´¢å¼•ã€è?ä¸Šï?ä¸æ?è®“æ•´ç­†åŒ¯?¥è¢«è¦–ç‚ºå¤±æ???
    }
    return insertedBook;
  }
```

- [x] **Step 4ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè??šé?**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: PASSï¼ˆæ–°å¢?4 ?…æ¸¬è©¦ï??¢æ??¨éƒ¨æ¸¬è©¦?†é€šé??”â€”é€™å€‹æ?æ¡ˆæ¸¬è©¦é?å¤§ï??´æ??è?ç¢ºä?æ²’æ??´å??¢æ??¯å…¥è¡Œç‚ºï¼‰ã€?

- [x] **Step 5ï¼š`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6ï¼šCommit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(search): ?°åŒ¯?¥æ›¸ç±çµ±ä¸€????¨æ?æª¢ç´¢ç´¢å??€?‹ï?Issue 2ï¼?
```

---

### Task 3ï¼šé??°ä?è¼‰å??ä?ä»¶é€??

**Filesï¼?*
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfacesï¼?*
- Consumesï¼šTask 1 ??`FullTextSearchSettingsRepository.handleBookAvailable(Book book)`ï¼ˆé€é??¢æ? `widget.readerFeatureRepositories.fullTextSearchSettingsRepository` ä¾è³´æ³¨å…¥è·¯å?ï¼ŒIssue 3 å·²å»ºç«‹ï??¬å·¥?®ä??€è¦æ–°å¢ä»»ä½•ä?è³´æ³¨??wiringï¼‰ã€?

- [x] **Step 1ï¼šå¯«ä¸€çµ„æ?å¤±æ??„æ¸¬è©?*

??`app/test/screens/library_screen_test.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

import '../support/fake_full_text_search_settings_repository.dart';
```

??`group('Issue 4ï¼šå?ä¸‹è??¸ç??æ–°ä¸‹è?', () { ... });` ?€å¡Šå…§ï¼Œæ‰¾?°æ—¢?‰æ¸¬è©?`'ç¢ºè?å¾Œæ??Ÿé??°ä?è¼‰ï??´æ–° filePath/isDownloadedï¼Œä?å»ºç??°ç? Book è¨˜é?'` çµå°¾ä¹‹å?ï¼Œæ–°å¢ï?

```dart
    testWidgets(
        '?æ–°ä¸‹è?å®Œæ?å¾Œå‘¼??fullTextSearchSettingsRepository.handleBookAvailable'
        'ï¼ˆepic-10-search Issue 2ï¼?, (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      final fullTextSearchSettingsRepository =
          FakeFullTextSearchSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              fullTextSearchSettingsRepository:
                  fullTextSearchSettingsRepository,
            ),
            isMobileDataConnection: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_redownload_confirm_button')),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        fullTextSearchSettingsRepository.handleBookAvailableCalls,
        hasLength(1),
      );
      final calledWith =
          fullTextSearchSettingsRepository.handleBookAvailableCalls.single;
      expect(calledWith.id, 'b1');
      expect(calledWith.isDownloaded, isTrue);
    });
```

- [x] **Step 2ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè?? ç‚º production è¡Œç‚ºå°šæœªå¯¦ä??Œå¤±??*

Run: `flutter test test/screens/library_screen_test.dart`
Expected: FAILï¼ˆ`fullTextSearchSettingsRepository.handleBookAvailableCalls` ?ºç©ºï¼Œæ–·è¨€ `hasLength(1)` å¤±æ?ï¼‰ã€?

- [x] **Step 3ï¼šå¯¦ä½?*

??`app/lib/screens/library_screen.dart`ï¼Œæ‰¾?°ï?

```dart
      final permanentPath = await promoteToPermanent(tempPath);

      await widget.repository.updateBook(
        book.copyWith(filePath: permanentPath, isDownloaded: true),
      );
      if (!mounted) return;
      await _bookListController.loadBooks();
```

?–ä»£?ºï?

```dart
      final permanentPath = await promoteToPermanent(tempPath);

      final updatedBook = book.copyWith(
        filePath: permanentPath,
        isDownloaded: true,
      );
      await widget.repository.updateBook(updatedBook);
      // epic-10-search Issue 2ï¼ˆspec.md Â§7ï¼‰ï??æ–°ä¸‹è?å®Œæ?ï¼æ—¢??
      // content_index_status ?—å·²? å??ç??Œç§»?¤æœ¬æ©Ÿå¿«?–ã€è¢«æ¸…ç©ºï¼ˆè???
      // è¨ˆç•« Task 4ï¼‰ï?æ­¤è?è£œä?å°æ???unsupported/pending æ¨™è?ï¼Œè??™æœ¬
      // ?¸é??°å??°æ­£ç¢ºç?ç´¢å??€?‹ã€‚search-index ?ªæ˜¯è¡ç?è³‡æ?ï¼Œå¯«?¥å¤±??
      // ä¸æ?è®“ä½¿?¨è€…çœ¼ä¸­ã€Œæ?æ¡ˆå·²ä¸‹è??å??è¢«èª¤åˆ¤?ºå¤±??
      // ï¼ˆreview-plan-issue-2.md M-1ï¼‰ã€?
      try {
        await widget
            .readerFeatureRepositories.fullTextSearchSettingsRepository
            ?.handleBookAvailable(updatedBook);
      } catch (_) {
        // ?œé??¥é??”â€”æ?æ¡ˆä?è¼‰è?è³‡æ?åº«æ?è¨˜æ›´?°æ??¯æ ¸å¿ƒæ?ä½œï?ç´¢å??€?‹å¯
        // ?¥å??é??Œé?å»ºç´¢å¼•ã€è?ä¸Šã€?
      }
      if (!mounted) return;
      await _bookListController.loadBooks();
```

- [x] **Step 4ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè??šé?**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASSï¼ˆæ–°å¢æ¸¬è©¦ï??¢æ??¨éƒ¨æ¸¬è©¦?†é€šé??”â€”é€™æ˜¯?¬å?æ¡ˆæ?å¤§ç?æ¸¬è©¦æª”ä?ä¸€ï¼Œæ•´æª”é?è·‘ç¢ºä¿æ??‰ç ´å£æ—¢?‰é??°ä?è¼??¸æ¶è¡Œç‚ºï¼‰ã€?

- [x] **Step 5ï¼š`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6ï¼šCommit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(search): ?æ–°ä¸‹è?å®Œæ?å¾Œé€???¨æ?æª¢ç´¢ç´¢å??€?‹ï?Issue 2ï¼?
```

---

### Task 4ï¼šç§»?¤æœ¬æ©Ÿå¿«?–ä?ä»¶é€??

**Filesï¼?*
- Modify: `app/lib/screens/library_batch_actions.dart`
- Test: `app/test/screens/library_batch_actions_test.dart`

**Interfacesï¼?*
- Consumesï¼šTask 1 ??`FullTextSearchSettingsRepository.clearBookIndex(String bookId)`??
- Producesï¼š`LibraryBatchActions` å»ºæ?å­æ–°å¢å¯?¸å…·?å???`FullTextSearchSettingsRepository? fullTextSearchSettingsRepository`ï¼ˆ`null` ?‚è??ºè??¾è?å®Œå…¨ä¸€?´ï??”â€”ä? Task 5 ?é? `library_screen.dart` ?¢æ? `_batchActions = LibraryBatchActions(...)` å»ºæ?é»æ³¨?¥ã€?

- [x] **Step 1ï¼šå¯«ä¸€çµ„æ?å¤±æ??„æ¸¬è©?*

??`app/test/screens/library_batch_actions_test.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

import '../support/fake_full_text_search_settings_repository.dart';
```

?¨æ—¢??`'removeLocalCache() ?ªè??†é¸?–é??ˆä¸­?¦â€?` æ¸¬è©¦ä¹‹å??`main()` ?¶å°¾ `}` ä¹‹å?ï¼Œæ–°å¢ï?

```dart
  test(
      'removeLocalCache() å°è¢«?•ç??„æ›¸ç±å‘¼??clearBookIndex æ¸…é™¤?œå?ç´¢å?'
      'ï¼ˆepic-10-search Issue 2ï¼?, () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', source: BookSource.calibreOpds, isDownloaded: true),
      _book(id: '2', source: BookSource.local, isDownloaded: true),
    ]);
    final fullTextSearchSettingsRepository =
        FakeFullTextSearchSettingsRepository();
    final actions = LibraryBatchActions(
      repository: repository,
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
    );
    final books = await repository.listBooks();

    await actions.removeLocalCache({'1', '2'}, books);

    // ?¸ç? 2 ??local ä¾†æ?ï¼ŒshouldInclude ?æ¿¾å¾Œä??ƒè¢«?•ç?ï¼Œåª?‰æ›¸ç±?1
    // ?‰è©²è§¸ç™¼ clearBookIndex??
    expect(fullTextSearchSettingsRepository.clearBookIndexCalls, ['1']);
  });
```

- [x] **Step 2ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè?? ç‚º production API å°šä?å­˜åœ¨?Œç·¨è­¯å¤±??*

Run: `flutter test test/screens/library_batch_actions_test.dart`
Expected: FAILï¼ˆç·¨è­¯éŒ¯èª¤ï?`LibraryBatchActions` æ²’æ? `fullTextSearchSettingsRepository` ?·å??ƒæ•¸ï¼‰ã€?

- [x] **Step 3ï¼šå¯¦ä½?*

??`app/lib/screens/library_batch_actions.dart`ï¼Œæ–¼ import ?€å¡Šæ–°å¢ï?

```dart
import '../search/full_text_search_settings_repository.dart';
```

?¾åˆ°ï¼?

```dart
class LibraryBatchActions {
  const LibraryBatchActions({required this.repository});

  final LibraryRepository repository;
```

?–ä»£?ºï?

```dart
class LibraryBatchActions {
  const LibraryBatchActions({
    required this.repository,
    this.fullTextSearchSettingsRepository,
  });

  final LibraryRepository repository;

  /// epic-10-search Issue 2ï¼ˆspec.md Â§7ï¼‰ï?ç§»é™¤?¬æ?å¿«å??‚ä?ä½µæ??¤æ?å°?
  /// ç´¢å?è³‡æ??‚`null` ?‚ï?ä¾‹å??¢æ?æ¸¬è©¦?ªæ?ä¾›ï?å®Œå…¨?¥é?ï¼Œè??ºè??¬å·¥??
  /// ä¹‹å?å®Œå…¨ä¸€?´ã€?
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;
```

?¾åˆ°ï¼?

```dart
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // æª”æ??ªé™¤å¤±æ??‚é?é»˜ç•¥?â€”â€”è??™åº«æ¨™è??´æ–°?æ˜¯?¸å??ä???
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
```

?–ä»£?ºï?

```dart
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // æª”æ??ªé™¤å¤±æ??‚é?é»˜ç•¥?â€”â€”è??™åº«æ¨™è??´æ–°?æ˜¯?¸å??ä???
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
        try {
          await fullTextSearchSettingsRepository?.clearBookIndex(book.id);
        } catch (_) {
          // ?review-plan-issue-2.md M-1?‘é?é»˜ç•¥?â€”â€”é¿?å–®ä¸€?¸ç??„ç´¢å¼?
          // æ¸…é™¤?°å¸¸ä¸­æ–·?´å€‹æ‰¹æ¬¡è¿´?ˆï?å°è‡´å¾Œé¢å¹¾æœ¬?¸ç?å¯¦é?æª”æ?å¿«å??¡æ?
          // è¢«åˆª?¤ï?ç´¢å?è³‡æ??ºè??Ÿæ€§è??™ï?ç¶­è­·å¤±æ?ä¸æ?å½±éŸ¿?¸å??„å¿«??
          // ç§»é™¤?ä???
        }
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
```

- [x] **Step 4ï¼šåŸ·è¡Œæ¸¬è©¦ï?ç¢ºè??šé?**

Run: `flutter test test/screens/library_batch_actions_test.dart`
Expected: PASSï¼ˆæ–°å¢æ¸¬è©¦ï??¢æ??¨éƒ¨æ¸¬è©¦?†é€šé?ï¼‰ã€?

- [x] **Step 5ï¼š`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6ï¼šCommit**

```bash
git add app/lib/screens/library_batch_actions.dart app/test/screens/library_batch_actions_test.dart
git commit -m "feat(search): ç§»é™¤?¬æ?å¿«å??‚æ??¤å…¨?‡æª¢ç´¢ç´¢å¼•è??™ï?Issue 2ï¼?
```

---

### Task 5ï¼š`library_screen.dart` ä¾è³´æ³¨å…¥è½‰é€ï?`didUpdateWidget` ?Œæ­¥ï¼‹`main.dart` çµ„è?

**Filesï¼?*
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`

**Interfacesï¼?*
- Consumesï¼šTask 2 ??`BookImportServiceImpl.fullTextSearchSettingsRepository` å»ºæ??ƒæ•¸?Task 4 ??`LibraryBatchActions.fullTextSearchSettingsRepository` å»ºæ??ƒæ•¸?æ—¢??`SqliteFullTextSearchSettingsRepository`??
- Producesï¼šç„¡?°å…¬??APIï¼ˆç?çµ„è?ï¼‰ï???Task å®Œæ?å¾?CBZ ?¯å…¥æ¨™è?ï¼æ–°?¸åŒ¯?¥å?å¡«ï??æ–°ä¸‹è?äº‹ä»¶ï¼ç§»?¤å¿«?–ä?ä»¶åœ¨æ­?? App ä¸­å³?¯é?ä½œã€?

??Task ?¯ç?çµ„è?ç¨‹å?ç¢¼ï?ä¸æ¡?¨ã€Œå?å¯«å¤±?—æ¸¬è©¦ã€ç? TDD æ­¥é?ï¼Œç›´?¥ä¿®?¹ï?é©—è?ï¼ˆ`library_screen.dart` ?™ä??•æ”¹?•å·²è¢?Task 3ï¼Task 4 ?„æ—¢?‰æ¸¬è©¦é??¥è??‹â€”â€”`LibraryBatchActions` å»ºæ?é»è‹¥å¿˜è??³å…¥?°å??¸ï?Task 4 ?°å??„æ¸¬è©¦ä??ƒå?æ­¤å¤±?—ï?? ç‚º???æ¸¬è©¦?´æ¥å»ºæ? `LibraryBatchActions` ?Œä?ç¶“é? `LibraryScreen`ï¼›å?æ­¤æœ¬ Task Step 3 ?ƒé?å¤–æ??•é?è­‰é€™ä???wiringï¼Œè?ä¸‹æ–¹ï¼‰ã€?

- [x] **Step 1ï¼š`library_screen.dart` ??`fullTextSearchSettingsRepository` è½‰é€çµ¦ `LibraryBatchActions`ï¼Œä¸¦??`didUpdateWidget()` ?Œæ­¥ï¼ˆreview-plan-issue-2.md M-2ï¼?*

??`app/lib/screens/library_screen.dart`ï¼Œæ‰¾?°ï?

```dart
    _batchActions = LibraryBatchActions(repository: widget.repository);
```

?–ä»£?ºï?

```dart
    _batchActions = LibraryBatchActions(
      repository: widget.repository,
      fullTextSearchSettingsRepository:
          widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
    );
```

?¾åˆ°ï¼?

```dart
  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    }
  }
```

?–ä»£?ºï?

```dart
  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onExternalRefreshRequested);
      widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    }
    // ?review-plan-issue-2.md M-2?‘_batchActions ??initState() å»ºæ???
    // ?•æ?äº†ç•¶ä¸‹ç? repository/fullTextSearchSettingsRepository ?ƒè€ƒï?
    // LibraryReaderFeatureRepositories æ²’æ?è¦†å¯« ==ï¼ˆé?è¨­å??ƒç›¸ç­‰ï?ï¼Œä?å±?
    // æ¯æ¬¡ build() ?æ–°å»ºæ??™å€?bundle ?‚é€™è£¡å¹¾ä??½æ??¤å??ºã€Œå·²è®Šæ›´?è€?
    // ?æ–°å»ºæ? _batchActions?”â€”æ??¬æ¥µä½ï?ç´”è??™æ??‰ç‰©ä»¶ï?ï¼Œä??€è¦é?å¤?
    // ?ªå?ï¼Œé?é»æ˜¯ä¸éºæ¼ç?æ­???¿æ??…å???
    if (widget.readerFeatureRepositories != oldWidget.readerFeatureRepositories ||
        widget.repository != oldWidget.repository) {
      _batchActions = LibraryBatchActions(
        repository: widget.repository,
        fullTextSearchSettingsRepository:
            widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
      );
    }
  }
```

- [x] **Step 2ï¼š`main.dart` ?æ–°?’å?å»ºæ??†å?ï¼Œä¸¦?³å…¥ `BookImportServiceImpl`**

??`app/lib/main.dart`ï¼Œæ‰¾?°ï?

```dart
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
  );
  // BookReaderPrefsRepository å¿…é???repository ?±ç”¨?Œä???Database ???
  // ï¼ˆbook_reader_prefs ?„å??µç??Ÿè?æ±‚ï?è¦?epic-3-fonts-layout Issue 1 spec.mdï¼‰ã€?
  // ?¨é€™è£¡ï¼ˆrepository å°šæœª?¶ç???LibraryRepository ä»‹é¢?ï??–ç”¨
  // SqliteLibraryRepository ?·è±¡?‹åˆ¥?æ???.database getterï¼ˆè?
  // docs/adr/0007-reader-screen-book-id-contract.mdï¼‰ã€?
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-10-search Issue 1ï¼šè??¯å…¨?‡æª¢ç´¢ç´¢å¼•å??ã€‚æœ¬å·¥å–®?ªè?è²¬è?å¼•æ?
  // ?½é?ä½œï??Œå??¨å…¨?‡æª¢ç´¢ã€é??œè??¹æ¬¡?å¡«?¢æ??¸åº«??Issue 3 ?„ç??â€”â€?
  // ?®å? content_index_status è£¡ä??ƒæ?ä»»ä? pending ?—ï??’ç??¨å??•å?
  // ç´”ç²¹?’ç½®ç­‰å?ï¼Œç›´??Issue 3 ?½åœ°?æ??‰å¯¦?›å·¥ä½œå¯?šã€?
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
  // epic-10-search Issue 3ï¼šã€Œå??¨å…¨?‡æª¢ç´¢ã€è¨­å®šæ¨¡?‹ã€‚requestProcessing
  // ä»?callback æ³¨å…¥ï¼ˆè€Œé??´æ¥?æ??´å€?contentIndexingSchedulerï¼‰ï?è¦?
  // plans/plan-issue-3.md Global Constraints??
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
```

?–ä»£?ºï?

```dart
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  // BookReaderPrefsRepository å¿…é???repository ?±ç”¨?Œä???Database ???
  // ï¼ˆbook_reader_prefs ?„å??µç??Ÿè?æ±‚ï?è¦?epic-3-fonts-layout Issue 1 spec.mdï¼‰ã€?
  // ?¨é€™è£¡ï¼ˆrepository å°šæœª?¶ç???LibraryRepository ä»‹é¢?ï??–ç”¨
  // SqliteLibraryRepository ?·è±¡?‹åˆ¥?æ???.database getterï¼ˆè?
  // docs/adr/0007-reader-screen-book-id-contract.mdï¼‰ã€?
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
  final bookmarksRepository = BookmarksRepository(repository.database);
  final highlightsRepository = HighlightsRepository(repository.database);
  final notesRepository = NotesRepository(repository.database);
  final customFontsRepository = CustomFontsRepository(repository.database);
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-10-search Issue 1ï¼šè??¯å…¨?‡æª¢ç´¢ç´¢å¼•å??ã€‚æœ¬å·¥å–®?ªè?è²¬è?å¼•æ?
  // ?½é?ä½œï??Œå??¨å…¨?‡æª¢ç´¢ã€é??œè??¹æ¬¡?å¡«?¢æ??¸åº«??Issue 3 ?„ç??â€”â€?
  // ?®å? content_index_status è£¡ä??ƒæ?ä»»ä? pending ?—ï??’ç??¨å??•å?
  // ç´”ç²¹?’ç½®ç­‰å?ï¼Œç›´??Issue 3 ?½åœ°?æ??‰å¯¦?›å·¥ä½œå¯?šã€?
  final readerActivityTracker = ReaderActivityTracker();
  final contentIndexingScheduler = ContentIndexingScheduler(
    database: repository.database,
    activityTracker: readerActivityTracker,
    pdfIndexer: const PdfContentIndexer(),
    foliateIndexer: const FoliateContentIndexer(),
  );
  contentIndexingScheduler.start();
  // epic-10-search Issue 3ï¼šã€Œå??¨å…¨?‡æª¢ç´¢ã€è¨­å®šæ¨¡?‹ã€‚requestProcessing
  // ä»?callback æ³¨å…¥ï¼ˆè€Œé??´æ¥?æ??´å€?contentIndexingSchedulerï¼‰ï?è¦?
  // plans/plan-issue-3.md Global Constraints??
  final fullTextSearchSettingsRepository =
      SqliteFullTextSearchSettingsRepository(
    database: repository.database,
    requestProcessing: contentIndexingScheduler.requestProcessing,
  );
  // epic-10-search Issue 2ï¼šæ–°?¸åŒ¯?¥ï???CBZ æ¨™è? unsupportedï¼‰é?è¦?
  // fullTextSearchSettingsRepositoryï¼ˆè? plans/plan-issue-2.mdï¼‰ï?? æ­¤
  // importService ?„å»ºæ§‹æŒª?°é€™è£¡ï¼ˆåœ¨å®ƒä?å¾Œï?ï¼Œä??æ˜¯ repository ?‹å?å¾?
  // ç«‹åˆ»å»ºæ???
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
    fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
  );
```

- [x] **Step 3ï¼šæ??•é?è­?`library_screen.dart` ??wiringï¼ˆTask 4 æ¸¬è©¦?¡æ?è¦†è??™ä??•ï?**

Run: `flutter analyze`ï¼ˆå?ç¢ºè??‹åˆ¥æ­?¢º?æ??‰éºæ¼ç??·å??ƒæ•¸ï¼?
Expected: `No issues found!`

?¥è??·è? `app/test/screens/library_screen_test.dart` ?¢æ??„ç§»?¤å¿«?–ç›¸?œæ¸¬è©¦ï?ç¢ºè??™ä??¢æ?æ¸¬è©¦??wiring è®Šæ›´å¾Œä??¶å…¨?¸é€šé??”â€”ä??€è¦æ–°å¢æ¸¬è©¦ï?? ç‚º `LibraryBatchActions` ?¬èº«??`clearBookIndex` ?¼å«?è¼¯å·²ç”± Task 4 ?„å–®?ƒæ¸¬è©¦é?ä½ï??™è£¡?ªé?è¦ç¢ºèªã€Œé€é? `LibraryScreen` çµ„è??‚æ??‰å?è¨˜å‚³?¥æ–°?ƒæ•¸å°è‡´ç·¨è­¯?¯èª¤?–åŸ·è¡Œæ?ä¾‹å??ï?

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASSï¼ˆå…¨?¸é€šé?ï¼Œå«?¢æ?ç§»é™¤å¿«å??¸é?æ¸¬è©¦ï¼‰ã€?

- [x] **Step 4ï¼šè??¬æ¬¡?¨éƒ¨?°å?è§¸å??„æ¸¬è©¦æ?ï¼Œç¢ºèªæ•´é«”æ??‰å?æ­?*

Run: `flutter test test/search/full_text_search_settings_repository_test.dart test/library/book_import_service_test.dart test/screens/library_screen_test.dart test/screens/library_batch_actions_test.dart`
Expected: PASSï¼ˆæœ¬è¨ˆç•«?°å??‡ä¿®?¹ç??€?‰æ¸¬è©¦æ??†é€šé?ï¼›`main.dart` ?¬èº«?¡å??‰æ¸¬è©¦æ?ï¼Œæ­£ç¢ºæ€§å·²?±ä?è¿°æ¸¬è©¦æ?æ¶µè??„ä?è³´æ³¨?¥è·¯å¾‘ï?`flutter analyze` ?‹åˆ¥æª¢æŸ¥æ¶µè?ï¼‰ã€?

- [x] **Step 5ï¼š`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6ï¼šCommit**

```bash
git add app/lib/screens/library_screen.dart app/lib/main.dart
git commit -m "feat(search): library_screen/main.dart çµ„è? Issue 2 ç´¢å??€?‹é€??ï¼ˆIssue 2ï¼?
```

- [x] **Step 7ï¼šï?äººé?ï¼åŸ·è¡Œè€…æ??•ï??Ÿæ??–æ¨¡?¬å™¨é©—è?**

`flutter run` ?Ÿå? Appï¼Œç¢ºèªï?
1. ?¨ã€Œè¨­å®šâ??±è??é??Ÿã€Œå…¶ä»–æ ¼å¼å…¨?‡æª¢ç´¢ã€é??œå?ï¼ŒåŒ¯?¥ä??¬æ–°??EPUBï¼Œç¢ºèªè©²?¸å?å¿«å‡º?¾ä?ç­?`content_index_status.status='pending'` ä¸¦è¢«?’ç??¨è??†å??ï?ä¸é?è¦æ??•é??‹é??œæ??å»ºç´¢å?ï¼‰â€”â€”é€™æ˜¯?¬è¼ªå¯©æŸ¥ï¼ˆC-2ï¼‰ä¿®æ­???¸å??…å?ï¼Œå?å¿…å¯¦æ¸¬é?è­‰ã€?
2. ?¯å…¥ä¸€??CBZ æ¼«ç•«ï¼Œç¢ºèªè©²??`content_index_status.status == 'unsupported'`ï¼Œæ?ç¨‹å™¨ä¸æ??—è©¦?•ç?å®ƒã€?
3. ?¥æ?å·²é€????Calibre/OPDS ? ç«¯?¸åº«ç«™é?ï¼šå?ä¸€?¬å·²ä¸‹è??„æ›¸?·è??Œç§»?¤æœ¬æ©Ÿå¿«?–ã€ï?ç¢ºè?è©²æ›¸??`content_index_status`ï¼`book_content_index` è³‡æ??—è¢«æ¸…ç©ºï¼›æ¥?—ã€Œé??°ä?è¼‰ã€ï??¥å??‰å?é¡ï?PDFï¼å…¶ä»–æ ¼å¼ï??®å?å·²å??¨ï?ç¢ºè?è©²æ›¸?æ–°?ºç¾ä¸€ç­?`status='pending'` ä¸¦æ?çµ‚è¢«?’ç??¨è??†å??ï?ä¸é?è¦é?å¤–æ??•è§¸?¼ã€?

ï¼ˆæœ¬ Task ä¸é?è¦è??¨å?æ¡?`flutter test`?”â€”ä?ä½¿ç”¨?…æ?ç¤ºï?Epic 10 å°šæ? Issue 4ï¼? ?ªå??ï?ä¸æ˜¯?€å¾Œä???Issueï¼Œå…¨å¥—æ¸¬è©¦ç??°æ•´??Epic ?¶å°¾?å?è·‘ä?æ¬¡ï?æ¯”ç…§ `plan-issue-3.md`ï¼`plan-issue-6.md` å·²æ¡?¨ç??¢æ?????‚ï?

---

## ?ªæ?å¯©æŸ¥ï¼ˆSelf-Reviewï¼Œè??«æ’°å¯«è€…åŸ·è¡Œï??å¦ä¸€è¼ªå¯©?¥ï?

**Spec è¦†è?åº¦ï?** spec.md Â§7 ä¸‰å€‹æ®µ?½é€é?å°æ??”â€?1)?ŒCBZï¼DRM KF8ï¼š`content_index_status.status = 'unsupported'`?â? CBZ ??Task 1ï¼ˆ`markUnsupported`ï¼Œç? `handleBookAvailable` çµ±ä??¥å£ï¼‰ï?Task 2ï¼ˆåŒ¯?¥æ??¼å«ï¼‰è½?°ï?DRM KF8 ?¥è?å¾Œç¢ºèªç¾è¡Œæ¶æ§‹ä???`Book` è¨˜é??¯æ?è¨˜ï?å·²åœ¨ Global Constraints ?ç¢ºè¨˜é??¥è??ç??‡äººé¡æ??¿ç??•ç??¹å?ï¼Œä?å¯¦ä?ä»»ä?ç¨‹å?ç¢¼ã€?2)?Œä?è¼‰å??â?ä¾å?é¡å??¨ç??‹æ±ºå®šæ˜¯?¦æ???pending?â? Task 1ï¼ˆ`handleBookAvailable`ï¼Œå·²ä¿®æ­£ C-1 ?šé??’ç??¨è? I-1 `isDownloaded` ?²ç¦¦ï¼‰ï?Task 2ï¼?*?°å?**ï¼šæ??‰æ ¼å¼ç??°åŒ¯?¥æ›¸ç±çµ±ä¸€???ï¼Œä¿®æ­??è¨ˆç•« C-2 ?ºæ?ï¼‰ï?Task 3ï¼ˆ`_handleRedownload` ?¼å«?¢æ??æ–°ä¸‹è??´æ™¯ï¼‰ã€?3)?Œç§»?¤å¿«?–â?æ¸…é™¤ç´¢å??â? Task 1ï¼ˆ`clearBookIndex`ï¼Œå·²ä¿®æ­£ I-2 è£œé? `book_content_fts` é©—è?ï¼‰ï?Task 4ï¼ˆ`removeLocalCache` ?¼å«ï¼Œå·²ä¾?M-1 ? ä? try/catchï¼‰ï?Task 5ï¼ˆ`LibraryScreen` è½‰é€?wiringï¼Œå·²ä¾?M-2 ? ä? `didUpdateWidget` ?Œæ­¥ï¼‰ã€‚issues.md Issue 2 ?®å?æ¸¬è©¦è¦æ?ä¸‰é?ï¼šã€ŒCBZï¼DRM KF8 ?¯å…¥å¾?unsupported ä¸”æ?ç¨‹å™¨?’é™¤?â? Task 2 æ¸¬è©¦ï¼ˆCBZ ?¨å?ï¼‰ï??¢æ? `_formatFilterFor()`ï¼ˆIssue 3 ?¢ç‰©ï¼‰æœ¬èº«å·²ä¿è??’ç??¨æ??¤ï?DRM KF8 ?¨å?? ç„¡ Book è¨˜é??Œç„¡?€æ¸¬è©¦?‚ã€Œä?è¼‰å??ä?ä»¶è§¸?¼å??ºç¾ pending?â? Task 1ï¼Task 2ï¼ˆæ–°?¯å…¥?´æ™¯ï¼‰ï?Task 3ï¼ˆé??°ä?è¼‰å ´?¯ï?æ¸¬è©¦ï¼Œä??†å·²é©—è? `requestProcessingCallCount` ç¢ºå¯¦?å??‚ã€Œç§»?¤å¿«?–ä?ä»¶è§¸?¼å?ä¸‰å¼µè¡¨è??™å??†æ?ç©ºã€â? Task 1ï¼ˆ`clearBookIndex` ?Œæ??•ç? `book_content_index`ï¼`content_index_status`ï¼`book_content_fts`ï¼Œå·²ä¾?I-2 è£œé?ä¸‰å¼µè¡¨é?è­‰ï???

**Placeholder ?ƒæ?ï¼?* ?¡ã€ŒTBD?ã€Œç?å¾Œè?ä¸Šã€ã€Œé?ä¼?Task N?ç?å­—æ¨£ï¼Œæ??‰ç?å¼ç¢¼?‡æ®µ?†ç‚ºå®Œæ•´?¯ç›´?¥å??¨ç??§å®¹??

**?‹åˆ¥ä¸€?´æ€§ï?** `markUnsupported(String bookId)`ï¼`handleBookAvailable(Book book)`ï¼`clearBookIndex(String bookId)` ??Task 1 å®šç¾©ï¼ˆæŠ½è±¡ä??¢ï?å¯¦ä?ï¼‹Fakeï¼‰ï?Task 2ï¼?ï¼? ?„å‘¼?«ç«¯å¼•æ•¸?‹åˆ¥?‡å…·?æ–¹å¼å??¨ä??´ï?`handleBookAvailable` ?½å?å·²å??Ÿè??«ç¬¬ä¸€?ˆç? `handleDownloadCompleted` ?¨é¢?¹å?ï¼ŒTask 1ï½? ??Fake ?„å‘¼?«è??„æ???`handleBookAvailableCalls` ?½å?ä¸€?´ï?ï¼›`BookImportServiceImpl.fullTextSearchSettingsRepository`ï¼`LibraryBatchActions.fullTextSearchSettingsRepository` ?©å€‹æ–°å»ºæ??ƒæ•¸??Task 2ï¼? å®šç¾©?Task 5 `main.dart`ï¼`library_screen.dart` ?¼å«ç«¯å‘½?ä??´ã€?
