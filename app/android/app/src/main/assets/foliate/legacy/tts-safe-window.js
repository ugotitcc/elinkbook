const TTS_SAFE_WINDOW_MIN = 0.2;
const TTS_SAFE_WINDOW_MAX = 0.8;
function resolveTtsSafeWindowDirection(firstRect, lastRect, iframeRect, viewportRect, isVertical) {
  if (!firstRect || !lastRect || !iframeRect || !viewportRect || !viewportRect.width || !viewportRect.height) {
    return null;
  }
  const normOf = (rect) => ({
    x: (iframeRect.left + (rect.left + rect.right) / 2 - viewportRect.left) / viewportRect.width,
    y: (iframeRect.top + (rect.top + rect.bottom) / 2 - viewportRect.top) / viewportRect.height
  });
  const first = normOf(firstRect);
  const last = normOf(lastRect);
  const needNext = isVertical ? last.x < TTS_SAFE_WINDOW_MIN || last.y > 1 : last.y > TTS_SAFE_WINDOW_MAX || last.x > 1;
  const needPrev = isVertical ? first.x > 1 || first.y < 0 : first.y < 0 || first.x < 0;
  if (needNext) return "next";
  if (needPrev) return "prev";
  return null;
}
export {
  resolveTtsSafeWindowDirection
};
