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
  function initReaderDemo() {
    const pageView = document.getElementById('demo-reader-view');
    if (!pageView) return;

    // 排版模式切換 (直排 / 橫排)
    const btnVertical = document.getElementById('btn-mode-vertical');
    const btnHorizontal = document.getElementById('btn-mode-horizontal');

    if (btnVertical && btnHorizontal) {
      btnVertical.addEventListener('click', () => {
        pageView.classList.remove('mode-horizontal');
        pageView.classList.add('mode-vertical');
        btnVertical.classList.add('active');
        btnHorizontal.classList.remove('active');
        const modeLabel = document.getElementById('demo-mode-indicator');
        if (modeLabel) modeLabel.textContent = '直排模式 (Vertical RTL)';
      });

      btnHorizontal.addEventListener('click', () => {
        pageView.classList.remove('mode-vertical');
        pageView.classList.add('mode-horizontal');
        btnHorizontal.classList.add('active');
        btnVertical.classList.remove('active');
        const modeLabel = document.getElementById('demo-mode-indicator');
        if (modeLabel) modeLabel.textContent = '橫排模式 (Horizontal LTR)';
      });
    }

    // 背景材質切換 (竹韻紙質 / E-Ink / 深色墨夜)
    const themeParchment = document.getElementById('theme-parchment-btn');
    const themeEink = document.getElementById('theme-eink-btn');
    const themeDark = document.getElementById('theme-dark-btn');

    if (themeParchment && themeEink && themeDark) {
      themeParchment.addEventListener('click', () => {
        pageView.className = pageView.className.replace(/theme-\w+/g, '') + ' theme-parchment';
        setActiveChip([themeParchment, themeEink, themeDark], themeParchment);
      });

      themeEink.addEventListener('click', () => {
        pageView.className = pageView.className.replace(/theme-\w+/g, '') + ' theme-eink';
        setActiveChip([themeParchment, themeEink, themeDark], themeEink);
      });

      themeDark.addEventListener('click', () => {
        pageView.className = pageView.className.replace(/theme-\w+/g, '') + ' theme-dark';
        setActiveChip([themeParchment, themeEink, themeDark], themeDark);
      });
    }
  }

  function setActiveChip(group, activeItem) {
    group.forEach((item) => item.classList.remove('active'));
    activeItem.classList.add('active');
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
