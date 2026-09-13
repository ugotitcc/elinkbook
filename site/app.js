/**
 * elinkBook (易閱書) - SPA 互動與路由核心腳本
 */

(function () {
  'use strict';

  // 路由對照表
  const routes = {
    '': 'view-home',
    '#': 'view-home',
    '#/': 'view-home',
    '#/home': 'view-home',
    '#/features': 'view-home',
    '#/specs': 'view-home',
    '#/privacy': 'view-privacy',
    '#/terms': 'view-terms',
    '#/download': 'view-home',
  };

  /**
   * 初始化深色 / 淺色主題
   */
  function initTheme() {
    const savedTheme = localStorage.getItem('elinkbook_theme') || 'light';
    document.documentElement.setAttribute('data-theme', savedTheme);
    updateThemeIcon(savedTheme);

    const toggleBtn = document.getElementById('theme-toggle-btn');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => {
        const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
        const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', newTheme);
        localStorage.setItem('elinkbook_theme', newTheme);
        updateThemeIcon(newTheme);
      });
    }
  }

  function updateThemeIcon(theme) {
    const icon = document.getElementById('theme-icon');
    if (!icon) return;
    if (theme === 'dark') {
      // 顯示太陽圖標
      icon.innerHTML = `<path d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
    } else {
      // 顯示月亮圖標
      icon.innerHTML = `<path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
    }
  }

  /**
   * 處理 SPA 視圖切換
   */
  function handleRouting() {
    const hash = window.location.hash || '#/';
    const targetViewId = routes[hash] || 'view-home';

    // 切換視圖顯示
    const allViews = document.querySelectorAll('.spa-view');
    allViews.forEach((view) => {
      if (view.id === targetViewId) {
        view.classList.add('active-view');
      } else {
        view.classList.remove('active-view');
      }
    });

    // 更新導覽列選單選取狀態
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach((link) => {
      const href = link.getAttribute('href');
      if (href === hash || (hash === '#/' && href === '#/home')) {
        link.classList.add('active');
      } else {
        link.classList.remove('active');
      }
    });

    // 關閉手機版選單
    const mobileMenu = document.getElementById('nav-links-menu');
    if (mobileMenu && mobileMenu.classList.contains('nav-open')) {
      mobileMenu.classList.remove('nav-open');
    }

    // 滾動至對應區塊
    if (hash === '#/features') {
      const featEl = document.getElementById('features');
      if (featEl) featEl.scrollIntoView({ behavior: 'smooth' });
    } else if (hash === '#/specs') {
      const specEl = document.getElementById('specs');
      if (specEl) specEl.scrollIntoView({ behavior: 'smooth' });
    } else if (hash === '#/download') {
      const downEl = document.getElementById('download');
      if (downEl) downEl.scrollIntoView({ behavior: 'smooth' });
    } else {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    // 更新網頁標題
    if (targetViewId === 'view-privacy') {
      document.title = '隱私權保護政策 - elinkBook (易閱書)';
    } else if (targetViewId === 'view-terms') {
      document.title = '服務條款 - elinkBook (易閱書)';
    } else {
      document.title = 'elinkBook (易閱書) - 專為繁體中文直排與 E-Ink 打造的極致電子書閱讀器';
    }
  }

  /**
   * 初始化閱讀器互動模擬器
   */
  /**
   * 初始化閱讀器互動模擬器 (依據 prototype/eink_redesign_prototype.html 規範)
   */
  function initReaderDemo() {
    const readerContainer = document.getElementById('demo-reader-container');
    const pageView = document.getElementById('demo-reader-view');
    const textFlow = document.getElementById('demo-text-flow');
    const emulatorScreen = document.getElementById('emulator-screen');
    const toastEl = document.getElementById('demo-toast');
    if (!readerContainer || !pageView || !emulatorScreen) return;

    let toastTimer = null;

    // 觸發 E-Ink 瞬翻刷屏反轉閃爍
    function triggerEinkFlash() {
      emulatorScreen.classList.remove('eink-refresh');
      // 強制 reflow 以重新觸發 CSS animation
      void emulatorScreen.offsetWidth;
      emulatorScreen.classList.add('eink-refresh');
    }

    // 顯示電子墨水屏提示 Toast
    function showToast(message) {
      if (!toastEl) return;
      toastEl.textContent = message;
      toastEl.classList.remove('hidden');
      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        toastEl.classList.add('hidden');
      }, 1800);
    }

    // ==========================================
    // 1. 直排 / 橫排模式切換
    // ==========================================
    const btnVertical = document.getElementById('btn-mode-vertical');
    const btnHorizontal = document.getElementById('btn-mode-horizontal');
    const layoutDirVertical = document.getElementById('layout-dir-vertical');
    const layoutDirHorizontal = document.getElementById('layout-dir-horizontal');

    function setDirection(mode) {
      if (mode === 'vertical') {
        pageView.classList.remove('mode-horizontal');
        pageView.classList.add('mode-vertical');
        if (btnVertical) btnVertical.classList.add('active');
        if (btnHorizontal) btnHorizontal.classList.remove('active');
        if (layoutDirVertical) layoutDirVertical.classList.add('active');
        if (layoutDirHorizontal) layoutDirHorizontal.classList.remove('active');
        showToast('已切換至繁體直排模式 (Vertical RTL)');
      } else {
        pageView.classList.remove('mode-vertical');
        pageView.classList.add('mode-horizontal');
        if (btnHorizontal) btnHorizontal.classList.add('active');
        if (btnVertical) btnVertical.classList.remove('active');
        if (layoutDirHorizontal) layoutDirHorizontal.classList.add('active');
        if (layoutDirVertical) layoutDirVertical.classList.remove('active');
        showToast('已切換至現代橫排模式 (Horizontal LTR)');
      }
      triggerEinkFlash();
    }

    if (btnVertical) btnVertical.addEventListener('click', () => setDirection('vertical'));
    if (btnHorizontal) btnHorizontal.addEventListener('click', () => setDirection('horizontal'));
    if (layoutDirVertical) layoutDirVertical.addEventListener('click', () => setDirection('vertical'));
    if (layoutDirHorizontal) layoutDirHorizontal.addEventListener('click', () => setDirection('horizontal'));

    // ==========================================
    // 2. 主題切換 (E-Ink / 紙質 / 夜間)
    // ==========================================
    const themeEinkBtn = document.getElementById('theme-eink-btn');
    const themeParchmentBtn = document.getElementById('theme-parchment-btn');
    const themeDarkBtn = document.getElementById('theme-dark-btn');
    const themeChips = [themeEinkBtn, themeParchmentBtn, themeDarkBtn].filter(Boolean);

    function setTheme(themeName, activeBtn, toastMsg) {
      readerContainer.className = readerContainer.className.replace(/theme-\w+/g, '').trim() + ' ' + themeName;
      themeChips.forEach(chip => chip.classList.remove('active'));
      if (activeBtn) activeBtn.classList.add('active');
      showToast(toastMsg);
      triggerEinkFlash();
    }

    if (themeEinkBtn) {
      themeEinkBtn.addEventListener('click', () => {
        setTheme('theme-eink', themeEinkBtn, '已套用 E-Ink 純黑白高對比模式');
      });
    }
    if (themeParchmentBtn) {
      themeParchmentBtn.addEventListener('click', () => {
        setTheme('theme-parchment', themeParchmentBtn, '已套用古典竹韻紙質模式');
      });
    }
    if (themeDarkBtn) {
      themeDarkBtn.addEventListener('click', () => {
        setTheme('theme-dark', themeDarkBtn, '已套用墨夜深色模式');
      });
    }

    // ==========================================
    // 3. 全螢幕沉浸閱讀切換 (⬓ 或點擊閱讀區)
    // ==========================================
    const topChrome = document.getElementById('reader-top-chrome');
    const normalChrome = document.getElementById('reader-normal-chrome');
    const ttsChrome = document.getElementById('reader-tts-chrome');
    const btnFullscreen = document.getElementById('btn-reader-fullscreen');
    let isChromeVisible = true;

    function toggleFullscreenChrome() {
      isChromeVisible = !isChromeVisible;
      if (isChromeVisible) {
        if (topChrome) topChrome.classList.remove('hidden');
        if (isTtsActive) {
          if (ttsChrome) ttsChrome.classList.remove('hidden');
        } else {
          if (normalChrome) normalChrome.classList.remove('hidden');
        }
        showToast('已顯示工具列與導覽資訊');
      } else {
        if (topChrome) topChrome.classList.add('hidden');
        if (normalChrome) normalChrome.classList.add('hidden');
        if (ttsChrome) ttsChrome.classList.add('hidden');
        showToast('已進入全螢幕沉浸閱讀模式');
      }
      triggerEinkFlash();
    }

    if (btnFullscreen) btnFullscreen.addEventListener('click', toggleFullscreenChrome);
    pageView.addEventListener('click', (e) => {
      // 點擊內文且非選取反白時切換工具列
      if (window.getSelection && window.getSelection().toString().length > 0) return;
      toggleFullscreenChrome();
    });

    // ==========================================
    // 4. 一般閱讀列按鈕互動 (返回、搜尋、目錄、書籤、劃線、跳頁)
    // ==========================================
    const btnBack = document.getElementById('btn-reader-back');
    const btnSearch = document.getElementById('btn-reader-search');
    const btnToc = document.getElementById('btn-reader-toc');
    const btnJump = document.getElementById('btn-reader-jump');
    const btnBookmark = document.getElementById('btn-nav-bookmark');
    const btnNotes = document.getElementById('btn-nav-notes');

    if (btnBack) btnBack.addEventListener('click', () => {
      showToast('返回書架 (Library)');
      triggerEinkFlash();
    });
    if (btnSearch) btnSearch.addEventListener('click', () => {
      showToast('開啟全文即時搜尋');
      triggerEinkFlash();
    });
    if (btnToc) btnToc.addEventListener('click', () => {
      showToast('開啟書籍目錄清單 (TOC)');
      triggerEinkFlash();
    });
    if (btnJump) btnJump.addEventListener('click', () => {
      showToast('跳轉至第 184 頁 / 共 468 頁 (39%)');
      triggerEinkFlash();
    });
    if (btnBookmark) btnBookmark.addEventListener('click', () => {
      showToast('已於目前進度新增書籤 ⚑');
      triggerEinkFlash();
    });
    if (btnNotes) btnNotes.addEventListener('click', () => {
      showToast('開啟劃線備註與筆記列表 ✎');
      triggerEinkFlash();
    });

    // ==========================================
    // 5. TTS 朗讀工具列互動 (2c)
    // ==========================================
    const btnNavTts = document.getElementById('btn-nav-tts');
    const ttsSentence = document.getElementById('demo-tts-sentence');
    const ttsPlayBtn = document.getElementById('tts-play-btn');
    const ttsPrevBtn = document.getElementById('tts-prev-btn');
    const ttsNextBtn = document.getElementById('tts-next-btn');
    const ttsSpeedBtn = document.getElementById('tts-speed-btn');
    const ttsVoiceBtn = document.getElementById('tts-voice-btn');
    const ttsTimerBtn = document.getElementById('tts-timer-btn');
    const ttsCollapseBtn = document.getElementById('tts-collapse-btn');
    const ttsStopBtn = document.getElementById('tts-stop-btn');
    const ttsExpandedControls = document.getElementById('tts-expanded-controls');

    let isTtsActive = false;
    let isTtsPlaying = true;
    let isTtsCollapsed = false;

    const demoSentences = [
      '像是某種只有自己讀得懂的記號。',
      '窗外的雨已經下了整個下午，屋簷的水線連成一片，',
      '把對面那排老屋的輪廓洗得模糊。',
      '「再一次。」老師沒有抬頭，只是把譜翻過一頁。'
    ];
    let sentenceIndex = 0;

    function startTts() {
      isTtsActive = true;
      isTtsPlaying = true;
      if (normalChrome) normalChrome.classList.add('hidden');
      if (ttsChrome) ttsChrome.classList.remove('hidden');
      if (ttsSentence) {
        ttsSentence.className = 'tts-sentence active-sentence';
        ttsSentence.textContent = demoSentences[sentenceIndex];
      }
      if (ttsPlayBtn) {
        ttsPlayBtn.textContent = '⏸ 暫停';
      }
      showToast('語音朗讀開始，切換為朗讀工具列');
      triggerEinkFlash();
    }

    function stopTts() {
      isTtsActive = false;
      if (ttsChrome) ttsChrome.classList.add('hidden');
      if (isChromeVisible && normalChrome) normalChrome.classList.remove('hidden');
      if (ttsSentence) {
        ttsSentence.className = 'tts-sentence';
        ttsSentence.textContent = demoSentences[0];
      }
      sentenceIndex = 0;
      showToast('已停止朗讀，回到一般閱讀工具列');
      triggerEinkFlash();
    }

    if (btnNavTts) btnNavTts.addEventListener('click', startTts);
    if (ttsStopBtn) ttsStopBtn.addEventListener('click', stopTts);

    if (ttsPlayBtn) {
      ttsPlayBtn.addEventListener('click', () => {
        isTtsPlaying = !isTtsPlaying;
        if (isTtsPlaying) {
          ttsPlayBtn.textContent = '⏸ 暫停';
          if (ttsSentence) ttsSentence.className = 'tts-sentence active-sentence';
          showToast('繼續語音朗讀');
        } else {
          ttsPlayBtn.textContent = '▶ 播放';
          if (ttsSentence) ttsSentence.className = 'tts-sentence paused-sentence';
          showToast('語音朗讀已暫停');
        }
        triggerEinkFlash();
      });
    }

    if (ttsPrevBtn) {
      ttsPrevBtn.addEventListener('click', () => {
        if (sentenceIndex > 0) {
          sentenceIndex--;
          if (ttsSentence) ttsSentence.textContent = demoSentences[sentenceIndex];
          showToast(`朗讀前一句：${demoSentences[sentenceIndex]}`);
          triggerEinkFlash();
        } else {
          showToast('已是本章開頭第一句');
        }
      });
    }

    if (ttsNextBtn) {
      ttsNextBtn.addEventListener('click', () => {
        if (sentenceIndex < demoSentences.length - 1) {
          sentenceIndex++;
          if (ttsSentence) ttsSentence.textContent = demoSentences[sentenceIndex];
          showToast(`朗讀下一句：${demoSentences[sentenceIndex]}`);
          triggerEinkFlash();
        } else {
          showToast('已到達示範章節尾端');
        }
      });
    }

    const speedOptions = ['1.0x', '1.25x', '1.5x', '0.8x'];
    let speedIndex = 0;
    if (ttsSpeedBtn) {
      ttsSpeedBtn.addEventListener('click', () => {
        speedIndex = (speedIndex + 1) % speedOptions.length;
        ttsSpeedBtn.textContent = speedOptions[speedIndex];
        showToast(`已調整朗讀語速為 ${speedOptions[speedIndex]}`);
        triggerEinkFlash();
      });
    }

    if (ttsVoiceBtn) {
      ttsVoiceBtn.addEventListener('click', () => {
        showToast('已切換朗讀語音：台灣繁體中文（自然女聲）');
        triggerEinkFlash();
      });
    }

    if (ttsTimerBtn) {
      ttsTimerBtn.addEventListener('click', () => {
        showToast('已設定睡眠定時器：30 分鐘後自動停止');
        triggerEinkFlash();
      });
    }

    if (ttsCollapseBtn && ttsExpandedControls) {
      ttsCollapseBtn.addEventListener('click', () => {
        isTtsCollapsed = !isTtsCollapsed;
        if (isTtsCollapsed) {
          ttsExpandedControls.classList.add('hidden');
          ttsCollapseBtn.textContent = '展開控制列';
        } else {
          ttsExpandedControls.classList.remove('hidden');
          ttsCollapseBtn.textContent = '收合成細列';
        }
        triggerEinkFlash();
      });
    }

    // ==========================================
    // 6. 版面設定面板 (2d BottomSheet)
    // ==========================================
    const btnNavLayout = document.getElementById('btn-nav-layout');
    const layoutSheet = document.getElementById('reader-layout-sheet');
    const btnCloseLayout = document.getElementById('btn-close-layout');

    if (btnNavLayout && layoutSheet) {
      btnNavLayout.addEventListener('click', () => {
        layoutSheet.classList.remove('hidden');
        showToast('開啟版面設定面板');
        triggerEinkFlash();
      });
    }

    if (btnCloseLayout && layoutSheet) {
      btnCloseLayout.addEventListener('click', () => {
        layoutSheet.classList.add('hidden');
        showToast('已套用版面設定');
        triggerEinkFlash();
      });
    }

    // Tabs 切換 (文字 / 邊界 / 呈現 / 預設集)
    const tabButtons = document.querySelectorAll('.layout-tab-btn');
    const tabContents = {
      text: document.getElementById('tab-content-text'),
      margin: document.getElementById('tab-content-margin'),
      display: document.getElementById('tab-content-display'),
      presets: document.getElementById('tab-content-presets')
    };

    tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;
        tabButtons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        Object.keys(tabContents).forEach(key => {
          if (tabContents[key]) {
            if (key === tab) {
              tabContents[key].classList.remove('hidden');
              tabContents[key].classList.add('active');
            } else {
              tabContents[key].classList.add('hidden');
              tabContents[key].classList.remove('active');
            }
          }
        });
        triggerEinkFlash();
      });
    });

    // 字型循環切換
    const fontFamilies = [
      { name: '思源宋體', family: 'var(--font-serif)' },
      { name: '思源楷體', family: 'var(--font-kai)' },
      { name: '思源黑體', family: 'var(--font-sans)' }
    ];
    let fontIndex = 0;
    const btnCycleFont = document.getElementById('btn-cycle-font');
    const valFontFamily = document.getElementById('val-font-family');

    if (btnCycleFont && valFontFamily && textFlow) {
      btnCycleFont.addEventListener('click', () => {
        fontIndex = (fontIndex + 1) % fontFamilies.length;
        valFontFamily.textContent = fontFamilies[fontIndex].name;
        textFlow.style.fontFamily = fontFamilies[fontIndex].family;
        showToast(`字型已切換為：${fontFamilies[fontIndex].name}`);
        triggerEinkFlash();
      });
    }

    // 字級大小調節步進器
    let fontSize = 19;
    const btnFontDec = document.getElementById('btn-font-dec');
    const btnFontInc = document.getElementById('btn-font-inc');
    const valFontSize = document.getElementById('val-font-size');

    if (btnFontDec && btnFontInc && valFontSize && textFlow) {
      btnFontDec.addEventListener('click', () => {
        if (fontSize > 14) {
          fontSize--;
          valFontSize.textContent = fontSize;
          textFlow.style.fontSize = `${fontSize * 0.055}rem`;
          triggerEinkFlash();
        }
      });
      btnFontInc.addEventListener('click', () => {
        if (fontSize < 26) {
          fontSize++;
          valFontSize.textContent = fontSize;
          textFlow.style.fontSize = `${fontSize * 0.055}rem`;
          triggerEinkFlash();
        }
      });
    }

    // 行距調節步進器
    let lineHeightVal = 1.9;
    const btnLineDec = document.getElementById('btn-line-dec');
    const btnLineInc = document.getElementById('btn-line-inc');
    const valLineHeight = document.getElementById('val-line-height');

    if (btnLineDec && btnLineInc && valLineHeight && textFlow) {
      btnLineDec.addEventListener('click', () => {
        if (lineHeightVal > 1.4) {
          lineHeightVal = parseFloat((lineHeightVal - 0.1).toFixed(1));
          valLineHeight.textContent = lineHeightVal;
          textFlow.style.lineHeight = lineHeightVal;
          triggerEinkFlash();
        }
      });
      btnLineInc.addEventListener('click', () => {
        if (lineHeightVal < 2.5) {
          lineHeightVal = parseFloat((lineHeightVal + 0.1).toFixed(1));
          valLineHeight.textContent = lineHeightVal;
          textFlow.style.lineHeight = lineHeightVal;
          triggerEinkFlash();
        }
      });
    }

    // 邊界調節步進器
    let marginVal = 20;
    const btnMarginDec = document.getElementById('btn-margin-dec');
    const btnMarginInc = document.getElementById('btn-margin-inc');
    const valMargin = document.getElementById('val-margin-horizontal');

    if (btnMarginDec && btnMarginInc && valMargin && pageView) {
      btnMarginDec.addEventListener('click', () => {
        if (marginVal > 8) {
          marginVal -= 2;
          valMargin.textContent = marginVal;
          pageView.style.padding = `${marginVal}px`;
          triggerEinkFlash();
        }
      });
      btnMarginInc.addEventListener('click', () => {
        if (marginVal < 36) {
          marginVal += 2;
          valMargin.textContent = marginVal;
          pageView.style.padding = `${marginVal}px`;
          triggerEinkFlash();
        }
      });
    }

    // 呈現開關 (純黑白 E-Ink 模式)
    const switchEink = document.getElementById('switch-eink-toggle');
    if (switchEink) {
      switchEink.addEventListener('click', () => {
        const isActive = switchEink.classList.toggle('active');
        if (isActive) {
          setTheme('theme-eink', themeEinkBtn, '已開啟純黑白 E-Ink 高對比渲染');
        } else {
          setTheme('theme-parchment', themeParchmentBtn, '已關閉純黑白，切回古典紙質');
        }
      });
    }

    // 預設集套用
    const presetClassic = document.getElementById('preset-classic');
    const presetModern = document.getElementById('preset-modern');
    if (presetClassic && presetModern) {
      presetClassic.addEventListener('click', () => {
        presetClassic.classList.add('active');
        presetModern.classList.remove('active');
        setDirection('vertical');
        if (textFlow) textFlow.style.fontFamily = 'var(--font-serif)';
        if (valFontFamily) valFontFamily.textContent = '思源宋體';
        showToast('已套用預設集：經典古籍直排');
      });
      presetModern.addEventListener('click', () => {
        presetModern.classList.add('active');
        presetClassic.classList.remove('active');
        setDirection('horizontal');
        if (textFlow) textFlow.style.fontFamily = 'var(--font-sans)';
        if (valFontFamily) valFontFamily.textContent = '思源黑體';
        showToast('已套用預設集：現代小說橫排');
      });
    }
  }

  /**
   * 手機版選單切換
   */
  function initMobileMenu() {
    const toggleBtn = document.getElementById('nav-toggle');
    const navMenu = document.getElementById('nav-links-menu');
    if (toggleBtn && navMenu) {
      toggleBtn.addEventListener('click', () => {
        navMenu.classList.toggle('nav-open');
      });
    }
  }

  /**
   * 複製當前條款連結工具
   */
  window.copyCurrentUrl = function () {
    navigator.clipboard.writeText(window.location.href).then(() => {
      alert('網址已成功複製至剪貼簿！');
    }).catch(() => {
      prompt('請手動複製以下網址：', window.location.href);
    });
  };

  // 監聽 DOM 載入完成
  document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    initReaderDemo();
    initMobileMenu();
    handleRouting();

    // 監聽 Hash 變化
    window.addEventListener('hashchange', handleRouting);
  });
})();
