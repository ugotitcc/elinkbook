const PITCH_TOLERANCE = 1.5;
const MAX_COMPENSATION_ITERATIONS = 4;
function measureColumnPitch(rects, vertical) {
  if (!rects || rects.length < 2) return null;
  const r0 = rects[0];
  const r1 = rects[1];
  const pitch = Math.abs(vertical ? r1.top - r0.top : r1.left - r0.left);
  if (!(pitch > 0)) return null;
  const columnLength = vertical ? r0.height : r0.width;
  return { pitch, columnLength };
}
function isValidMaxHeight(px) {
  return Number.isFinite(px) && px > 0;
}
function nextMaxHeight(args) {
  const pitch = args.pitch;
  const target = args.target;
  const base = args.base;
  const error = pitch - target;
  if (Math.abs(error) < PITCH_TOLERANCE) return null;
  return base - error;
}
function compensateColumnPitch(args) {
  const target = args.target;
  const measure = args.measure;
  const getBoxHeight = args.getBoxHeight;
  const setMaxHeight = args.setMaxHeight;
  const resetMaxHeight = args.resetMaxHeight;
  let iterations = 0;
  let lastSetMaxHeight = null;
  for (let i = 0; i < MAX_COMPENSATION_ITERATIONS; i++) {
    const measured = measure();
    if (!measured) {
      if (i === 0) {
        return { status: "skipped", iterations: 0 };
      }
      resetMaxHeight();
      return { status: "gave-up", iterations };
    }
    const base = lastSetMaxHeight !== null ? lastSetMaxHeight : Math.min(getBoxHeight(), measured.columnLength);
    const next = nextMaxHeight({
      pitch: measured.pitch,
      target,
      base
    });
    if (next === null) {
      return {
        status: iterations === 0 ? "ok" : "compensated",
        iterations
      };
    }
    if (!isValidMaxHeight(next)) {
      resetMaxHeight();
      return { status: "gave-up", iterations };
    }
    setMaxHeight(next);
    lastSetMaxHeight = next;
    iterations++;
  }
  const finalMeasured = measure();
  if (finalMeasured && Math.abs(finalMeasured.pitch - target) < PITCH_TOLERANCE) {
    return { status: "compensated", iterations };
  }
  resetMaxHeight();
  return { status: "gave-up", iterations };
}
export {
  MAX_COMPENSATION_ITERATIONS,
  PITCH_TOLERANCE,
  compensateColumnPitch,
  isValidMaxHeight,
  measureColumnPitch,
  nextMaxHeight
};
