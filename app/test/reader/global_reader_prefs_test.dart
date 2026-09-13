import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';

void main() {
  test('GlobalReaderPrefs.initial() 的 4 個欄位皆為各自的 .initial()／預設值', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.consoleLogEnabled, isFalse);
    expect(prefs.navZone, const NavZonePrefs.initial());
    expect(prefs.tts, const TtsDefaults.initial());
    expect(prefs.reading, const ReadingDefaults.initial());
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs.initial();
    final updatedReading = original.copyWith(
      reading: original.reading.copyWith(pageTurnMode: PageTurnMode.scroll),
    );
    expect(updatedReading.reading.pageTurnMode, PageTurnMode.scroll);
    expect(updatedReading.navZone, original.navZone);
    expect(updatedReading.tts, original.tts);
    expect(updatedReading.consoleLogEnabled, original.consoleLogEnabled);
  });

  test('copyWith 可個別替換 navZone／tts／reading 整個子物件', () {
    const original = GlobalReaderPrefs.initial();
    const newNavZone = NavZonePrefs(navZoneMode: NavZoneMode.oneHand);
    const newTts = TtsDefaults(ttsVoiceId: 'voice-1');
    final updated = original.copyWith(navZone: newNavZone, tts: newTts);
    expect(updated.navZone, newNavZone);
    expect(updated.tts, newTts);
    expect(updated.reading, original.reading);
  });

  test('copyWith 可更新 consoleLogEnabled，不影響巢狀物件', () {
    const original = GlobalReaderPrefs.initial();
    final updated = original.copyWith(consoleLogEnabled: true);
    expect(updated.consoleLogEnabled, isTrue);
    expect(updated.navZone, original.navZone);
    expect(updated.tts, original.tts);
    expect(updated.reading, original.reading);
  });

  test('4 個欄位值皆相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      consoleLogEnabled: true,
      navZone: NavZonePrefs(navZoneMode: NavZoneMode.oneHand),
      tts: TtsDefaults(ttsVoiceId: 'voice-1'),
      reading: ReadingDefaults(pageTurnMode: PageTurnMode.scroll),
    );
    const b = GlobalReaderPrefs(
      consoleLogEnabled: true,
      navZone: NavZonePrefs(navZoneMode: NavZoneMode.oneHand),
      tts: TtsDefaults(ttsVoiceId: 'voice-1'),
      reading: ReadingDefaults(pageTurnMode: PageTurnMode.scroll),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一巢狀子物件不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    expect(
        a ==
            a.copyWith(
                navZone: const NavZonePrefs(navZoneMode: NavZoneMode.oneHand)),
        isFalse);
    expect(a == a.copyWith(tts: const TtsDefaults(ttsVoiceId: 'voice-1')),
        isFalse);
    expect(
        a ==
            a.copyWith(
                reading: const ReadingDefaults(
                    pageTurnMode: PageTurnMode.scroll)),
        isFalse);
    expect(a == a.copyWith(consoleLogEnabled: true), isFalse);
  });
}
