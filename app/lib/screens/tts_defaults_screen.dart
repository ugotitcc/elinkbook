import 'package:flutter/material.dart';

import '../reader/global_reader_prefs.dart';
import '../reader/reader_prefs_manager.dart';
import '../reader/tts_provider.dart';
import 'widgets/eb_section_header.dart';

/// 朗讀（TTS）預設值畫面（epic-36-adaptive-shelf-navigation spec.md
/// §功能⑤）：語音選擇＋預設語速，皆讀寫 [GlobalReaderPrefs]，比照既有
/// `ReadingDefaultsScreen`/`NavZoneSettingsScreen`「全域偏好、即時生效、
/// 無儲存按鈕」慣例。**播放端何時讀取套用為預設值不在本畫面範圍**——本畫面
/// 只負責把使用者選擇寫進 `GlobalReaderPrefs`，播放端串接留待下一個涉及
/// TTS 播放邏輯的 Epic（spec.md「Out of Scope」）。
class TtsDefaultsScreen extends StatefulWidget {
  final ReaderPrefsManager prefsManager;
  final TtsProvider? ttsProvider;
  final bool isEinkMode;

  const TtsDefaultsScreen({
    super.key,
    required this.prefsManager,
    this.ttsProvider,
    this.isEinkMode = false,
  });

  @override
  State<TtsDefaultsScreen> createState() => _TtsDefaultsScreenState();
}

class _TtsDefaultsScreenState extends State<TtsDefaultsScreen> {
  static const _minSpeed = 0.75;
  static const _maxSpeed = 2.0;
  static const _speedStep = 0.1;

  bool _loading = true;
  late GlobalReaderPrefs _prefs;
  List<TtsVoice> _voices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.prefsManager.loadGlobalPrefs();
    final voices = await widget.ttsProvider?.getAvailableVoices() ?? const [];
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _voices = voices;
      _loading = false;
    });
  }

  void _update(GlobalReaderPrefs updated) {
    widget.prefsManager.saveGlobalPrefs(updated);
    setState(() => _prefs = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('朗讀語音與語速')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('tts_defaults_loading_indicator'),
              ),
            )
          : ListView(
              children: [
                const EBSectionHeader(title: '語音'),
                // 【review-plan-issue-5.md I-2】ttsProvider 缺席「或」裝置
                // 雖有 TTS 引擎但回傳空清單（尚未安裝語言包）時，皆顯示同一
                // 個不可用提示，不留空白區塊。
                if (widget.ttsProvider == null || _voices.isEmpty)
                  const Padding(
                    key: Key('tts_defaults_voice_unavailable_hint'),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('目前裝置未安裝或不支援語音選擇'),
                  )
                else
                  RadioGroup<String>(
                    groupValue:
                        _prefs.tts.ttsVoiceId ?? TtsVoice.systemDefault.id,
                    onChanged: (voiceId) {
                      if (voiceId == null) return;
                      _update(
                        _prefs.copyWith(
                          tts: _prefs.tts.copyWith(ttsVoiceId: voiceId),
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        for (final voice in _voices)
                          RadioListTile<String>(
                            key: Key('tts_defaults_voice_${voice.id}'),
                            title: Text(voice.displayName),
                            value: voice.id,
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                const EBSectionHeader(title: '語速'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('tts_defaults_speed_decrement'),
                        icon: const Icon(Icons.remove),
                        // 【review-plan-issue-5.md C-1】停用判斷須看「目前值
                        // 是否已到達下限」，不能看「預判扣除一步後是否會低於
                        // 下限」——0.75 與預設起點 1.0 之間不是 0.1 的整數倍
                        // （1.0 - 0.75 = 0.25），若用後者，0.8x 時
                        // 0.8 - 0.1 = 0.7 < 0.75 已成立，按鈕會在到達 0.75x
                        // 之前就被錯誤停用，使用者永遠调不到規格下限。
                        onPressed:
                            _prefs.tts.defaultTtsSpeed <= _minSpeed + 1e-9
                            ? null
                            : () => _update(
                                _prefs.copyWith(
                                  tts: _prefs.tts.copyWith(
                                    defaultTtsSpeed:
                                        (_prefs.tts.defaultTtsSpeed -
                                                _speedStep)
                                            .clamp(_minSpeed, _maxSpeed),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: widget.isEinkMode
                            ? Text(
                                // 0.75（規格下限）不是 0.1 的整數倍，
                                // toStringAsFixed(1) 對半整數採四捨五入，
                                // 0.75.toStringAsFixed(1) 會誤顯示為
                                // "0.8"，須特判（review-issue-5.md
                                // Important 1）。
                                '${_prefs.tts.defaultTtsSpeed == _minSpeed ? '0.75' : _prefs.tts.defaultTtsSpeed.toStringAsFixed(1)}x',
                                key: const Key('tts_defaults_speed_value'),
                                textAlign: TextAlign.center,
                              )
                            : Slider(
                                key: const Key('tts_defaults_speed_slider'),
                                value: _prefs.tts.defaultTtsSpeed,
                                min: _minSpeed,
                                max: _maxSpeed,
                                // 【review-plan-issue-5.md I-1】不設
                                // divisions——(_maxSpeed - _minSpeed) /
                                // _speedStep = 1.25 / 0.1 = 12.5，四捨五入成
                                // 13 個刻度後，每格間距變成約 0.0962x，不只
                                // 不是 0.1 的整數倍，連基準語速 1.0x 都不落在
                                // 任何一個刻度上。改為連續 Slider，實際的
                                // 0.1x 步進吸附放在 onChanged 內以四捨五入
                                // 達成，確保 Slider 拖曳與下方 E-Ink +/-
                                // 按鈕產生的是同一組可達值。
                                label:
                                    '${_prefs.tts.defaultTtsSpeed.toStringAsFixed(2)}x',
                                onChanged: (v) {
                                  // 規格下限 0.75 不是 0.1 的整數倍：
                                  // (v * 10).round() / 10 對 v 恰為
                                  // _minSpeed 時仍四捨五入成 0.8（7.5
                                  // 四捨五入進位），導致拖曳 Slider
                                  // 永遠到不了 0.75x（review-issue-5.md
                                  // Important 2）。v 貼近下限時直接吸附
                                  // 至 _minSpeed，其餘沿用原本 0.1 步進
                                  // 四捨五入。
                                  final snapped = v <= _minSpeed + 0.025
                                      ? _minSpeed
                                      : (v * 10).round() / 10;
                                  _update(
                                    _prefs.copyWith(
                                      tts: _prefs.tts.copyWith(
                                        defaultTtsSpeed: snapped.clamp(
                                          _minSpeed,
                                          _maxSpeed,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      IconButton(
                        key: const Key('tts_defaults_speed_increment'),
                        icon: const Icon(Icons.add),
                        // 【review-plan-issue-5.md C-1】同上改看「目前值」
                        // 而非「預判下一步」——上限側目前用預設起點 1.0
                        // 推算剛好落在整數格上不會复現同一個 bug，但停用
                        // 判斷式仍須與下限側維持同一套邏輯（看目前值），
                        // 否則 Slider 端四捨五入吸附（見下方 I-1 修正）
                        // 得出的浮點值一旦有極小誤差飄出格線，預判式會比
                        // 目前值式更早停用，行為不一致、也更脆弱。
                        onPressed:
                            _prefs.tts.defaultTtsSpeed >= _maxSpeed - 1e-9
                            ? null
                            : () => _update(
                                _prefs.copyWith(
                                  tts: _prefs.tts.copyWith(
                                    defaultTtsSpeed:
                                        (_prefs.tts.defaultTtsSpeed +
                                                _speedStep)
                                            .clamp(_minSpeed, _maxSpeed),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
