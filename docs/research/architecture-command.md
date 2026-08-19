┌─────────────────────────────────────────────────────────────────────────────┐
│                              Flutter Reader App                              │
│                                                                             │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────────┐  │
│  │    Library UI    │   │    Reader UI     │   │     Settings / AI      │  │
│  │                  │   │                  │   │                        │  │
│  │ • Bookshelf      │   │ • Page           │   │ • Theme                │  │
│  │ • Collections    │   │ • TOC            │   │ • Font                 │  │
│  │ • Search         │   │ • Search         │   │ • Chinese Conversion   │  │
│  │ • Metadata       │   │ • Highlight      │   │ • TTS                  │  │
│  └────────┬─────────┘   │ • Notes          │   │ • AI Translation       │  │
│           │             └────────┬─────────┘   │ • Summary               │  │
│           │                      │             └────────────┬───────────┘  │
│           └──────────────────────┼──────────────────────────┘              │
│                                  │                                         │
│                     ┌────────────▼────────────┐                            │
│                     │    Application Layer    │                            │
│                     │                         │                            │
│                     │ • Book Manager          │                            │
│                     │ • Reading Manager       │                            │
│                     │ • Annotation Manager    │                            │
│                     │ • Sync Manager          │                            │
│                     └────────────┬────────────┘                            │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
             ┌─────────────────────┼──────────────────────────┐
             │                     │                          │
             ▼                     ▼                          ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────────┐
│   BOOK SOURCE LAYER  │  │   READING DATA       │  │   SYNC / BACKEND LAYER │
│                      │  │                      │  │                        │
│ 「書從哪裡來？」       │  │ 「閱讀產生什麼資料？」 │  │ 「資料如何同步？」        │
│                      │  │                      │  │                        │
│ • Local File         │  │ • Reading Progress   │  │      PocketBase        │
│ • Google Drive       │  │ • Bookmark           │  │          │             │
│ • OneDrive           │  │ • Highlight          │  │          ▼             │
│ • WebDAV             │  │ • Note               │  │   ┌──────────────┐     │
│ • OPDS               │  │ • Annotation         │  │   │ PocketBase   │     │
│ • Calibre            │  │ • Reading Session    │  │   │              │     │
│ • Obsidian*          │  │ • TTS State           │  │   │ Auth         │     │
│                      │  │                      │  │   │ Collections  │     │
└──────────┬───────────┘  └──────────┬───────────┘  │   │ Realtime     │     │
           │                         │              │   │ API          │     │
           │                         │              │   └──────────────┘     │
           │                         │              └────────────────────────┘
           ▼                         ▼
┌──────────────────────┐  ┌──────────────────────────────────────────────────┐
│   BOOK IMPORTER      │  │             LOCAL READING DATABASE               │
│                      │  │                                                  │
│ • Download           │  │ • Books                                           │
│ • Validate           │  │ • BookIdentity                                    │
│ • Hash               │  │ • ReadingProgress                                │
│ • Metadata           │  │ • Bookmark                                        │
│ • Cover              │  │ • Highlight                                       │
│ • File Version       │  │ • Note                                            │
└──────────┬───────────┘  │ • ReadingSession                                  │
           │              │ • SyncState                                       │
           ▼              └───────────────────────┬──────────────────────────┘
┌──────────────────────┐                          │
│    LOCAL BOOK STORE  │                          │
│                      │                          │
│ books/{bookId}/      │                          │
│   ├── book.epub      │                          │
│   ├── cover.webp     │                          │
│   ├── metadata.json  │                          │
│   └── cache/         │                          │
└──────────┬───────────┘                          │
           │                                      │
           │                                      │
           └──────────────────┬───────────────────┘
                              ▼
                    ┌─────────────────────┐
                    │    READER ENGINE    │
                    │                     │
                    │ ReaderEngine        │
                    │ ReaderBridge        │
                    │ ReaderLocation      │
                    └──────────┬──────────┘
                               │
                            WebView
                               │
                               ▼
                    ┌─────────────────────┐
                    │      foliate-js     │
                    │                     │
                    │ • EPUB Parser       │
                    │ • Section Loader    │
                    │ • Pagination        │
                    │ • CFI               │
                    │ • Navigation        │
                    │ • Search            │
                    │ • Overlayer         │
                    │ • DOM               │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ TextTransform       │
                    │ Pipeline            │
                    │                     │
                    │ • OpenCC            │
                    │ • S2T               │
                    │ • S2TW              │
                    │ • T2S               │
                    │ • Sanitizer         │
                    │ • CSS               │
                    │ • Font              │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
       ┌────────────┐   ┌────────────┐   ┌──────────────┐
       │ Rendering  │   │   Search   │   │ Annotation   │
       │            │   │            │   │              │
       │ • Layout   │   │ • Original │   │ • Highlight  │
       │ • Theme    │   │ • S2TW     │   │ • Bookmark   │
       │ • Font     │   │ • T2S      │   │ • Note       │
       └────────────┘   └────────────┘   └──────┬───────┘
                                                │
                                                ▼
                                       Reading Data Manager
                                                │
                            ┌───────────────────┴──────────────────┐
                            │                                      │
                            ▼                                      ▼
                     Local Database                         Sync Manager
                            │                                      │
                            │                         ┌────────────┴───────────┐
                            │                         │                        │
                            │                         ▼                        ▼
                            │                  Offline Queue            PocketBase
                            │                                           │
                            │                                           ├── Auth
                            │                                           ├── Users
                            │                                           ├── Books
                            │                                           ├── Progress
                            │                                           ├── Bookmarks
                            │                                           ├── Highlights
                            │                                           ├── Notes
                            │                                           └── Sessions
                            │
                            └───────────────────────────────────────────────┐
                                                                            │
                                                                            ▼
                                                                  Other Devices
                                                                  ┌──────────────┐
                                                                  │ Android      │
                                                                  │ iOS          │
                                                                  │ Windows      │
                                                                  │ macOS        │
                                                                  └──────────────┘


                          ┌──────────────────────────────────────┐
                          │           SPEECH PIPELINE             │
                          │                                      │
                          │ Current Text                         │
                          │      ↓                               │
                          │ Text Transform                       │
                          │      ↓                               │
                          │ ┌────────┬────────┬───────────────┐ │
                          │ │ Local  │ Cloud  │ AI TTS        │ │
                          │ │ TTS    │ TTS    │               │ │
                          │ └────────┴────────┴───────────────┘ │
                          └──────────────────────────────────────┘



一、最重要的架構概念

系統會形成一個很清楚的關係：

書從哪裡來（Source）、書存在哪裡（Storage）、怎麼閱讀（Reader）、閱讀產生什麼資料（Reading Data）、怎麼同步（Sync） 是五個不同問題。

現在整個系統其實可以分成 6 個核心 Layer：
1. Application
        ↓
2. Book Source
        ↓
3. Book Storage
        ↓
4. Reader Engine
        ↓
5. Reading Data
        ↓
6. Sync / Backend

二、整個專案可以定義成（不含PDF的部份）
                         ┌──────────────────────┐
                         │     Flutter App      │
                         └──────────┬───────────┘
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       │                            │                            │
       ▼                            ▼                            ▼
 Book Source                    Reader Engine                AI / Speech
       │                            │                            │
       │                       foliate-js                       │
       │                            │                            │
       │                       Text Pipeline                    │
       │                            │                            │
       ▼                            ▼                            ▼
 Book Store                 Reading Data Manager          TTS / AI
       │                            │
       │                            ▼
       │                      Local Database
       │                            │
       │                      Sync Manager
       │                            │
       │                            ▼
       │                       PocketBase
       │                            │
       │                     ┌──────┴──────┐
       │                     │             │
       │                     ▼             ▼
       │                  Device A      Device B
       │
       ├── Local
       ├── Google Drive
       ├── OneDrive
       ├── WebDAV
       ├── OPDS
       ├── Calibre
       └── Obsidian*