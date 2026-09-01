# UI Design Rules

## Project

Flutter ebook reader.

## Core architecture

The following systems already work and must NOT be redesigned
or rewritten as part of UI work:

- EPUB parsing
- foliate-js
- EPUB CFI
- JavaScript bridge
- TTS synchronization
- Read-along synchronization
- PocketBase synchronization
- OPDS implementation
- WebDAV implementation
- Cloud Source implementation
- Book storage
- Reading progress persistence

## UI work may modify

- Flutter widgets
- Theme
- Design tokens
- Layout
- Navigation
- Dialogs
- Bottom sheets
- Reader controls
- Library UI
- Settings UI
- TTS controls
- Annotation UI

## Before changing code

First explain:

1. Which UI component will change
2. Why it needs to change
3. Which screens depend on it
4. Whether business logic is affected

Do not modify business logic during UI redesign.