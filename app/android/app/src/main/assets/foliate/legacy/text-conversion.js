import { s2tDict, t2sDict, s2twpPhraseDict, tw2sPhraseDict } from "./text_conversion_dict.js";
import { createOffsetMapBuilder } from "./text-offset-map.js";
const MAX_PHRASE_KEY_LENGTH = 16;
function applyTextConversionToString(text, mode) {
  if (mode === "original" || text.length === 0) {
    return { text, offsetMap: null };
  }
  const units = Array.from(text);
  let matchUnits;
  let charDict;
  let phraseDict;
  if (mode === "toTraditional") {
    charDict = s2tDict;
    phraseDict = s2twpPhraseDict;
    matchUnits = units.map((ch) => charDict[ch] || ch);
  } else {
    charDict = t2sDict;
    phraseDict = tw2sPhraseDict;
    matchUnits = units;
  }
  let result = "";
  const builder = createOffsetMapBuilder();
  let origOffset = 0;
  let dispOffset = 0;
  let i = 0;
  while (i < matchUnits.length) {
    const maxLen = Math.min(MAX_PHRASE_KEY_LENGTH, matchUnits.length - i);
    let matchedValue = null;
    let matchedLen = 0;
    for (let len = maxLen; len >= 1; len--) {
      const candidate = matchUnits.slice(i, i + len).join("");
      if (Object.prototype.hasOwnProperty.call(phraseDict, candidate)) {
        matchedValue = phraseDict[candidate];
        matchedLen = len;
        break;
      }
    }
    const consumedCount = matchedValue !== null ? matchedLen : 1;
    const origSegment = matchUnits.slice(i, i + consumedCount).join("");
    const dispSegment = matchedValue !== null ? matchedValue : mode === "toTraditional" ? origSegment : charDict[origSegment] || origSegment;
    result += dispSegment;
    if (dispSegment.length !== origSegment.length) {
      builder.addSegment(origOffset, origSegment.length, dispOffset, dispSegment.length);
    }
    origOffset += origSegment.length;
    dispOffset += dispSegment.length;
    i += consumedCount;
  }
  return { text: result, offsetMap: builder.build() };
}
function convertTtsSegments(segments, mode) {
  return segments.map((segment) => ({
    ...segment,
    text: applyTextConversionToString(segment.text, mode).text
  }));
}
export {
  applyTextConversionToString,
  convertTtsSegments
};
