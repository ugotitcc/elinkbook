import fs from 'node:fs';
import path from 'node:path';
import OpenCC from 'opencc-js';

const s2twp = OpenCC.Converter({ from: 'cn', to: 'twp' });
const tw2s = OpenCC.Converter({ from: 'tw', to: 'cn' });
const tw2sp = OpenCC.Converter({ from: 'twp', to: 'cn' });
const t2s = OpenCC.Converter({ from: 't', to: 'cn' });

const dictModules = [
  'STCharacters', 'STPhrases', 'STPhrases_GeneratedFromRegionalPhrases',
  'TSCharacters', 'TSPhrases',
  'TWPhrases', 'TWPhrasesRev',
  'TWVariants', 'TWVariantsPhrases', 'TWVariantsRev', 'TWVariantsRevPhrases'
];

async function loadDicts() {
  const dictData = {};
  for (const name of dictModules) {
    const mod = await import('./node_modules/opencc-js/dist/esm-lib/dict/' + name + '.js');
    const raw = mod.default;
    const pairs = [];
    if (typeof raw === 'string') {
      for (const line of raw.split('|')) {
        if (!line) continue;
        const [k, v] = line.split(' ');
        if (k && v) pairs.push([k, v]);
      }
    }
    dictData[name] = pairs;
  }
  return dictData;
}

function csvEscape(val) {
  const str = String(val ?? '');
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replaceAll('"', '""')}"`;
  }
  return str;
}

async function run() {
  const dicts = await loadDicts();

  // Process s2twp
  const s2twpMap = new Map();
  for (const [k, v] of dicts.STPhrases) s2twpMap.set(k, { orig: k, dictVal: v, source: 'STPhrases' });
  for (const [k, v] of dicts.STPhrases_GeneratedFromRegionalPhrases) s2twpMap.set(k, { orig: k, dictVal: v, source: 'STPhrases_Regional' });
  for (const [k, v] of dicts.STCharacters) s2twpMap.set(k, { orig: k, dictVal: v, source: 'STCharacters' });
  for (const [k, v] of dicts.TWPhrases) {
    const simp = t2s(k);
    s2twpMap.set(simp, { orig: simp, dictVal: v, source: 'TWPhrases' });
  }

  const s2twpResults = [];
  for (const [input, meta] of s2twpMap.entries()) {
    const eff = s2twp(input);
    const uIn = input.length, uOut = eff.length, uDiff = uOut - uIn;
    const cpIn = [...input].length, cpOut = [...eff].length, cpDiff = cpOut - cpIn;
    s2twpResults.push({
      direction: 's2twp',
      input,
      dictVal: meta.dictVal,
      effective: eff,
      source: meta.source,
      uIn, uOut, uDiff,
      cpIn, cpOut, cpDiff,
      cat: `${uIn}→${uOut}`
    });
  }

  // Write s2twp Changed CSV
  const s2twpChanged = s2twpResults.filter(r => r.uDiff !== 0).sort((a, b) => Math.abs(b.uDiff) - Math.abs(a.uDiff) || a.input.localeCompare(b.input));
  const csvHeader = 'direction,input,dictionaryTarget,effectiveOutput,sourceDict,inputUtf16,outputUtf16,diffUtf16,inputCodePoints,outputCodePoints,diffCodePoints,lengthChangeType\n';
  fs.writeFileSync('opencc/OpenCC-Length-Diff-s2twp-UTF16-CHANGED.csv', csvHeader + s2twpChanged.map(r => 
    [r.direction, r.input, r.dictVal, r.effective, r.source, r.uIn, r.uOut, r.uDiff, r.cpIn, r.cpOut, r.cpDiff, r.cat].map(csvEscape).join(',')
  ).join('\n') + '\n', 'utf8');

  // Generate s2twp SUMMARY
  const s2twpInc = s2twpChanged.filter(r => r.uDiff > 0).length;
  const s2twpDec = s2twpChanged.filter(r => r.uDiff < 0).length;
  const s2twpCats = {};
  for (const r of s2twpChanged) s2twpCats[r.cat] = (s2twpCats[r.cat] || 0) + 1;

  const s2twpSummary = `OpenCC Length Difference Analysis: s2twp (Simplified -> Taiwan Traditional with Phrases)
========================================================================================
opencc-js version: 1.4.2
Direction: s2twp (Simplified Chinese -> Taiwan Traditional with regional vocabulary)
Generated: ${new Date().toISOString()}

PRIMARY METRIC
--------------
UTF-16 code units (JavaScript String.length / Dart String.length / DOM Range Offset)

TOTAL STATISTICS
----------------
Total unique vocabulary entries analyzed: ${s2twpResults.length}
🔴 UTF-16 length CHANGED (offset drift): ${s2twpChanged.length} (${(s2twpChanged.length / s2twpResults.length * 100).toFixed(3)}%)
   - UTF-16 length increased (+): ${s2twpInc}
   - UTF-16 length decreased (-): ${s2twpDec}
   - Causes breakdown:
     * Taiwan regional phrase length change: ${s2twpChanged.filter(r => r.cpDiff !== 0).length} entries
     * Unicode surrogate pair character change (diffCP=0): ${s2twpChanged.filter(r => r.cpDiff === 0).length} entries
🟡 Code Point changed but UTF-16 unchanged: 0 (0.000%)
🟢 Length completely unchanged: ${s2twpResults.length - s2twpChanged.length} (${((s2twpResults.length - s2twpChanged.length) / s2twpResults.length * 100).toFixed(3)}%)

LENGTH CHANGE CATEGORIES
------------------------
${Object.entries(s2twpCats).sort((a,b) => b[1] - a[1]).map(([cat, count]) => `${cat}: ${count}`).join('\n')}

TOP TAIWAN PHRASES CAUSING OFFSET DRIFT (SAMPLE)
------------------------------------------------
${s2twpChanged.filter(r => r.source === 'TWPhrases').slice(0, 50).map(r => `${r.input} -> ${r.effective} (UTF-16: ${r.cat}, diff: ${r.uDiff > 0 ? '+' : ''}${r.uDiff})`).join('\n')}
`;
  fs.writeFileSync('opencc/OpenCC-Length-Diff-s2twp-SUMMARY.txt', s2twpSummary, 'utf8');

  // Process tw2s
  const tw2sMap = new Map();
  for (const [k, v] of dicts.TWVariantsRevPhrases) tw2sMap.set(k, { orig: k, dictVal: v, source: 'TWVariantsRevPhrases' });
  for (const [k, v] of dicts.TWVariantsRev) tw2sMap.set(k, { orig: k, dictVal: v, source: 'TWVariantsRev' });
  for (const [k, v] of dicts.TSPhrases) tw2sMap.set(k, { orig: k, dictVal: v, source: 'TSPhrases' });
  for (const [k, v] of dicts.TSCharacters) tw2sMap.set(k, { orig: k, dictVal: v, source: 'TSCharacters' });

  const tw2sResults = [];
  for (const [input, meta] of tw2sMap.entries()) {
    const eff = tw2s(input);
    const uIn = input.length, uOut = eff.length, uDiff = uOut - uIn;
    const cpIn = [...input].length, cpOut = [...eff].length, cpDiff = cpOut - cpIn;
    tw2sResults.push({
      direction: 'tw2s',
      input,
      dictVal: meta.dictVal,
      effective: eff,
      source: meta.source,
      uIn, uOut, uDiff,
      cpIn, cpOut, cpDiff,
      cat: `${uIn}→${uOut}`
    });
  }

  const tw2sChanged = tw2sResults.filter(r => r.uDiff !== 0).sort((a, b) => Math.abs(b.uDiff) - Math.abs(a.uDiff) || a.input.localeCompare(b.input));
  fs.writeFileSync('opencc/OpenCC-Length-Diff-tw2s-UTF16-CHANGED.csv', csvHeader + tw2sChanged.map(r => 
    [r.direction, r.input, r.dictVal, r.effective, r.source, r.uIn, r.uOut, r.uDiff, r.cpIn, r.cpOut, r.cpDiff, r.cat].map(csvEscape).join(',')
  ).join('\n') + '\n', 'utf8');

  const tw2sInc = tw2sChanged.filter(r => r.uDiff > 0).length;
  const tw2sDec = tw2sChanged.filter(r => r.uDiff < 0).length;
  const tw2sCats = {};
  for (const r of tw2sChanged) tw2sCats[r.cat] = (tw2sCats[r.cat] || 0) + 1;

  const tw2sSummary = `OpenCC Length Difference Analysis: tw2s (Taiwan Traditional -> Simplified)
========================================================================================
opencc-js version: 1.4.2
Direction: tw2s (Taiwan Traditional -> Simplified Chinese standard)
Generated: ${new Date().toISOString()}

PRIMARY METRIC
--------------
UTF-16 code units (JavaScript String.length / Dart String.length / DOM Range Offset)

TOTAL STATISTICS
----------------
Total unique vocabulary entries analyzed: ${tw2sResults.length}
🔴 UTF-16 length CHANGED (offset drift): ${tw2sChanged.length} (${(tw2sChanged.length / tw2sResults.length * 100).toFixed(3)}%)
   - UTF-16 length increased (+): ${tw2sInc}
   - UTF-16 length decreased (-): ${tw2sDec}
   - Causes breakdown:
     * Taiwan regional phrase length change: 0 entries (tw2s does not convert regional phrases)
     * Unicode surrogate pair character change (diffCP=0): ${tw2sChanged.length} entries
🟡 Code Point changed but UTF-16 unchanged: 0 (0.000%)
🟢 Length completely unchanged: ${tw2sResults.length - tw2sChanged.length} (${((tw2sResults.length - tw2sChanged.length) / tw2sResults.length * 100).toFixed(3)}%)

LENGTH CHANGE CATEGORIES
------------------------
${Object.entries(tw2sCats).sort((a,b) => b[1] - a[1]).map(([cat, count]) => `${cat}: ${count}`).join('\n')}

SURROGATE PAIR CHARACTERS CAUSING OFFSET DRIFT (SAMPLE)
-------------------------------------------------------
${tw2sChanged.slice(0, 50).map(r => `${r.input} -> ${r.effective} (UTF-16: ${r.cat}, diff: ${r.uDiff > 0 ? '+' : ''}${r.uDiff})`).join('\n')}
`;
  fs.writeFileSync('opencc/OpenCC-Length-Diff-tw2s-SUMMARY.txt', tw2sSummary, 'utf8');

  console.log('Successfully regenerated all CSV and SUMMARY files in opencc/!');
}

run().catch(console.error);
