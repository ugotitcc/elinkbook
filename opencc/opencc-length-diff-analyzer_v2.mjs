import fs from 'node:fs';
import path from 'node:path';

import OpenCC from 'opencc-js';
import * as Locale from 'opencc-js/preset';

/*
 * ============================================================
 * OpenCC Length Difference Analyzer v3
 * ============================================================
 *
 * Target:
 *
 *   s2twp
 *     Simplified Chinese
 *       ->
 *     Traditional Chinese (Taiwan)
 *
 *   tw2s
 *     Traditional Chinese (Taiwan)
 *       ->
 *     Simplified Chinese
 *
 *
 * IMPORTANT
 * ============================================================
 *
 * JavaScript String.length
 *     =
 * UTF-16 code units
 *
 * This is the primary metric because:
 *
 *   JavaScript DOM Text offset
 *       -> UTF-16
 *
 *   Dart String.length
 *       -> UTF-16
 *
 * Therefore UTF-16 is the important metric for:
 *
 *   EPUB
 *   foliate-js
 *   DOM Range
 *   TTS
 *   read-along highlight
 *   CFI / offset synchronization
 *
 *
 * OUTPUT
 * ============================================================
 *
 *   OpenCC-Length-Diff-s2twp-ALL.csv
 *   OpenCC-Length-Diff-s2twp-UTF16-CHANGED.csv
 *   OpenCC-Length-Diff-s2twp-SUMMARY.txt
 *
 *   OpenCC-Length-Diff-tw2s-ALL.csv
 *   OpenCC-Length-Diff-tw2s-UTF16-CHANGED.csv
 *   OpenCC-Length-Diff-tw2s-SUMMARY.txt
 *
 * ============================================================
 */

const VERSION = '1.4.2';

const OUTPUT_DIR = process.cwd();

const CONFIGS = ['s2twp', 'tw2s'];

/* ============================================================
 * Utility
 * ============================================================
 */

function utf16Length(value) {
  return value.length;
}

function codePointLength(value) {
  return Array.from(value).length;
}

function csvEscape(value) {
  const text = String(value ?? '');

  if (
    text.includes('"') ||
    text.includes(',') ||
    text.includes('\n') ||
    text.includes('\r')
  ) {
    return `"${text.replaceAll('"', '""')}"`;
  }

  return text;
}

function csvRow(values) {
  return values.map(csvEscape).join(',');
}

/* ============================================================
 * Recursive dictionary extraction
 * ============================================================
 */

function extractPairs(value, output = []) {
  if (value == null) {
    return output;
  }

  /*
   * Mapping:
   *
   *   [input, output]
   */
  if (
    Array.isArray(value) &&
    value.length >= 2 &&
    typeof value[0] === 'string' &&
    typeof value[1] === 'string'
  ) {
    output.push([value[0], value[1]]);

    return output;
  }

  /*
   * Nested array.
   */
  if (Array.isArray(value)) {
    for (const item of value) {
      extractPairs(item, output);
    }

    return output;
  }

  /*
   * Object.
   *
   * Some preset structures can contain dictionary groups
   * inside objects.
   */
  if (typeof value === 'object' && value !== null) {
    for (const item of Object.values(value)) {
      extractPairs(item, output);
    }
  }

  return output;
}

/* ============================================================
 * Unique pairs
 * ============================================================
 */

function uniquePairs(pairs) {
  const seen = new Set();

  const result = [];

  for (const pair of pairs) {
    const input = pair[0];
    const output = pair[1];

    const key = `${input}\u0000${output}`;

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);

    result.push([input, output]);
  }

  return result;
}

/* ============================================================
 * Preset dictionary extraction
 * ============================================================
 */

function getPresetPairs(configName) {
  /*
   * opencc-js preset structure.
   *
   * We intentionally inspect the preset itself rather than
   * inventing a new dictionary pipeline.
   */

  const config = Locale.configs?.[configName];

  if (!config) {
    throw new Error(`Cannot find preset config "${configName}".`);
  }

  const pairs = [];

  extractPairs(config, pairs);

  return uniquePairs(pairs);
}

/* ============================================================
 * Correct opencc-js Converter API
 * ============================================================
 */

function createConverter(configName) {
  /*
   * IMPORTANT:
   *
   * opencc-js Converter() expects an OPTIONS OBJECT.
   *
   * NOT:
   *
   *   Converter(Locale.from.cn, Locale.to.twp)
   *
   * Correct form:
   *
   *   Converter({
   *     from: ...,
   *     to: ...
   *   })
   */

  if (configName === 's2twp') {
    return OpenCC.Converter({
      from: 'cn',

      to: 'twp',
    });
  }

  if (configName === 'tw2s') {
    return OpenCC.Converter({
      from: 'twp',

      to: 'cn',
    });
  }

  throw new Error(`Unsupported config: ${configName}`);
}

/* ============================================================
 * Analyze one mapping
 * ============================================================
 */

function analyzeMapping(direction, input, dictionaryOutput, converter) {
  const normalizedInput = String(input ?? '');

  const normalizedDictionaryOutput = String(dictionaryOutput ?? '');

  let effectiveOutput;

  try {
    effectiveOutput = converter(normalizedInput);
  } catch (error) {
    /*
     * If the converter cannot process the particular
     * dictionary entry, retain the dictionary output.
     *
     * The error is not allowed to stop the complete scan.
     */

    effectiveOutput = normalizedDictionaryOutput;
  }

  const inputUtf16 = utf16Length(normalizedInput);

  const outputUtf16 = utf16Length(effectiveOutput);

  const diffUtf16 = outputUtf16 - inputUtf16;

  const inputCodePoints = codePointLength(normalizedInput);

  const outputCodePoints = codePointLength(effectiveOutput);

  const diffCodePoints = outputCodePoints - inputCodePoints;

  return {
    direction,

    input: normalizedInput,

    dictionaryOutput: normalizedDictionaryOutput,

    effectiveOutput,

    inputUtf16,

    outputUtf16,

    diffUtf16,

    inputCodePoints,

    outputCodePoints,

    diffCodePoints,

    lengthChangeType: `${inputUtf16}→${outputUtf16}`,

    codePointChangeType: `${inputCodePoints}→${outputCodePoints}`,
  };
}

/* ============================================================
 * Sorting
 * ============================================================
 */

function sortResults(results) {
  return [...results].sort((a, b) => {
    /*
     * UTF-16 changed first.
     */

    const aChanged = a.diffUtf16 !== 0;

    const bChanged = b.diffUtf16 !== 0;

    if (aChanged && !bChanged) {
      return -1;
    }

    if (!aChanged && bChanged) {
      return 1;
    }

    /*
     * Input length.
     */

    if (a.inputUtf16 !== b.inputUtf16) {
      return a.inputUtf16 - b.inputUtf16;
    }

    /*
     * Input text.
     */

    return a.input.localeCompare(b.input);
  });
}

/* ============================================================
 * Analyze config
 * ============================================================
 */

function analyzeConfig(configName) {
  console.log('');

  console.log('='.repeat(72));

  console.log(`Analyzing ${configName}`);

  console.log('='.repeat(72));

  /*
   * Create REAL converter.
   */

  const converter = createConverter(configName);

  /*
   * Extract dictionary mappings.
   */

  const pairs = getPresetPairs(configName);

  console.log(`Dictionary mappings found: ${pairs.length}`);

  const results = [];

  let index = 0;

  for (const [input, dictionaryOutput] of pairs) {
    index++;

    if (index % 5000 === 0) {
      console.log(`  processed ${index}/${pairs.length}`);
    }

    if (!input) {
      continue;
    }

    const result = analyzeMapping(
      configName,
      input,
      dictionaryOutput,
      converter,
    );

    results.push(result);
  }

  console.log(`Mappings analyzed: ${results.length}`);

  const changed = results.filter((item) => item.diffUtf16 !== 0);

  console.log(`UTF-16 changed: ${changed.length}`);

  return results;
}

/* ============================================================
 * Statistics
 * ============================================================
 */

function calculateStatistics(results) {
  const statistics = {
    total: results.length,

    utf16Unchanged: 0,

    utf16Changed: 0,

    utf16Increased: 0,

    utf16Decreased: 0,

    codePointUnchanged: 0,

    codePointChanged: 0,

    lengthPairs: new Map(),

    changedLengthPairs: new Map(),

    codePointPairs: new Map(),
  };

  for (const item of results) {
    /*
     * UTF-16
     */

    if (item.diffUtf16 === 0) {
      statistics.utf16Unchanged++;
    } else {
      statistics.utf16Changed++;
    }

    if (item.diffUtf16 > 0) {
      statistics.utf16Increased++;
    }

    if (item.diffUtf16 < 0) {
      statistics.utf16Decreased++;
    }

    /*
     * Code points
     */

    if (item.diffCodePoints === 0) {
      statistics.codePointUnchanged++;
    } else {
      statistics.codePointChanged++;
    }

    /*
     * UTF-16 pair
     */

    const lengthKey = `${item.inputUtf16}→${item.outputUtf16}`;

    statistics.lengthPairs.set(
      lengthKey,

      (statistics.lengthPairs.get(lengthKey) ?? 0) + 1,
    );

    /*
     * Changed UTF-16 pair only.
     */

    if (item.diffUtf16 !== 0) {
      statistics.changedLengthPairs.set(
        lengthKey,

        (statistics.changedLengthPairs.get(lengthKey) ?? 0) + 1,
      );
    }

    /*
     * Code point pair.
     */

    const codePointKey = `${item.inputCodePoints}→${item.outputCodePoints}`;

    statistics.codePointPairs.set(
      codePointKey,

      (statistics.codePointPairs.get(codePointKey) ?? 0) + 1,
    );
  }

  return statistics;
}

/* ============================================================
 * Sort length pair map
 * ============================================================
 */

function sortLengthPairs(map) {
  return [...map.entries()].sort((a, b) => {
    const [aInput, aOutput] = a[0].split('→').map(Number);

    const [bInput, bOutput] = b[0].split('→').map(Number);

    if (aInput !== bInput) {
      return aInput - bInput;
    }

    return aOutput - bOutput;
  });
}

/* ============================================================
 * Write ALL CSV
 * ============================================================
 */

function writeAllCsv(configName, results) {
  const fileName = `OpenCC-Length-Diff-${configName}-ALL.csv`;

  const filePath = path.join(OUTPUT_DIR, fileName);

  const headers = [
    'direction',

    'input',

    'dictionaryOutput',

    'effectiveOutput',

    'inputUtf16',

    'outputUtf16',

    'diffUtf16',

    'inputCodePoints',

    'outputCodePoints',

    'diffCodePoints',

    'lengthChangeType',

    'codePointChangeType',
  ];

  const lines = [csvRow(headers)];

  for (const item of sortResults(results)) {
    lines.push(
      csvRow([
        item.direction,

        item.input,

        item.dictionaryOutput,

        item.effectiveOutput,

        item.inputUtf16,

        item.outputUtf16,

        item.diffUtf16,

        item.inputCodePoints,

        item.outputCodePoints,

        item.diffCodePoints,

        item.lengthChangeType,

        item.codePointChangeType,
      ]),
    );
  }

  fs.writeFileSync(
    filePath,

    lines.join('\n') + '\n',

    'utf8',
  );

  console.log(`Created: ${fileName}`);
}

/* ============================================================
 * Write UTF-16 changed CSV
 * ============================================================
 */

function writeChangedCsv(configName, results) {
  const fileName = `OpenCC-Length-Diff-${configName}-UTF16-CHANGED.csv`;

  const filePath = path.join(OUTPUT_DIR, fileName);

  const changed = sortResults(results.filter((item) => item.diffUtf16 !== 0));

  const headers = [
    'direction',

    'input',

    'dictionaryOutput',

    'effectiveOutput',

    'inputUtf16',

    'outputUtf16',

    'diffUtf16',

    'inputCodePoints',

    'outputCodePoints',

    'diffCodePoints',

    'lengthChangeType',

    'codePointChangeType',
  ];

  const lines = [csvRow(headers)];

  for (const item of changed) {
    lines.push(
      csvRow([
        item.direction,

        item.input,

        item.dictionaryOutput,

        item.effectiveOutput,

        item.inputUtf16,

        item.outputUtf16,

        item.diffUtf16,

        item.inputCodePoints,

        item.outputCodePoints,

        item.diffCodePoints,

        item.lengthChangeType,

        item.codePointChangeType,
      ]),
    );
  }

  fs.writeFileSync(
    filePath,

    lines.join('\n') + '\n',

    'utf8',
  );

  console.log(`Created: ${fileName}`);

  console.log(`UTF-16 changed mappings: ${changed.length}`);
}

/* ============================================================
 * Summary
 * ============================================================
 */

function writeSummary(configName, results) {
  const statistics = calculateStatistics(results);

  const fileName = `OpenCC-Length-Diff-${configName}-SUMMARY.txt`;

  const filePath = path.join(OUTPUT_DIR, fileName);

  const lines = [];

  lines.push('OpenCC Length Difference Analysis');

  lines.push('================================');

  lines.push('');

  lines.push(`opencc-js target version: ${VERSION}`);

  lines.push(`Direction: ${configName}`);

  lines.push(`Generated: ${new Date().toISOString()}`);

  lines.push('');

  /*
   * Important explanation.
   */

  lines.push('PRIMARY METRIC');

  lines.push('--------------');

  lines.push('UTF-16 code units');

  lines.push('JavaScript String.length is UTF-16 code units.');

  lines.push('This matches JavaScript DOM Text offsets.');

  lines.push('Dart String.length also uses UTF-16 code units.');

  lines.push('');

  /*
   * Total.
   */

  lines.push('TOTAL');

  lines.push('-----');

  lines.push(`Total mappings: ${statistics.total}`);

  lines.push(`UTF-16 unchanged: ${statistics.utf16Unchanged}`);

  lines.push(`UTF-16 changed: ${statistics.utf16Changed}`);

  lines.push(`UTF-16 increased: ${statistics.utf16Increased}`);

  lines.push(`UTF-16 decreased: ${statistics.utf16Decreased}`);

  lines.push('');

  /*
   * Changed length categories.
   */

  lines.push('UTF-16 CHANGED LENGTH CATEGORIES');

  lines.push('--------------------------------');

  const changedPairs = sortLengthPairs(statistics.changedLengthPairs);

  if (changedPairs.length === 0) {
    lines.push('No UTF-16 length-changing mappings.');
  } else {
    for (const [key, count] of changedPairs) {
      lines.push(`${key}: ${count}`);
    }
  }

  lines.push('');

  /*
   * ALL length categories.
   */

  lines.push('ALL UTF-16 LENGTH CATEGORIES');

  lines.push('----------------------------');

  const allPairs = sortLengthPairs(statistics.lengthPairs);

  for (const [key, count] of allPairs) {
    lines.push(`${key}: ${count}`);
  }

  lines.push('');

  /*
   * Actual changed mappings.
   */

  lines.push('UTF-16 CHANGED MAPPINGS');

  lines.push('----------------------');

  const changed = sortResults(results.filter((item) => item.diffUtf16 !== 0));

  if (changed.length === 0) {
    lines.push('NONE');
  } else {
    for (const item of changed) {
      lines.push(`${item.input} → ${item.effectiveOutput}`);

      lines.push(
        `  UTF-16: ${item.inputUtf16} → ${item.outputUtf16} (${item.diffUtf16 >= 0 ? '+' : ''}${item.diffUtf16})`,
      );

      lines.push(
        `  Code Points: ${item.inputCodePoints} → ${item.outputCodePoints} (${item.diffCodePoints >= 0 ? '+' : ''}${item.diffCodePoints})`,
      );

      if (item.dictionaryOutput !== item.effectiveOutput) {
        lines.push(`  Dictionary: ${item.dictionaryOutput}`);
      }

      lines.push('');
    }
  }

  /*
   * Code point categories.
   */

  lines.push('CODE POINT LENGTH CATEGORIES');

  lines.push('----------------------------');

  const codePointPairs = sortLengthPairs(statistics.codePointPairs);

  for (const [key, count] of codePointPairs) {
    lines.push(`${key}: ${count}`);
  }

  lines.push('');

  /*
   * Output files.
   */

  lines.push('OUTPUT FILES');

  lines.push('------------');

  lines.push(`OpenCC-Length-Diff-${configName}-ALL.csv`);

  lines.push(`OpenCC-Length-Diff-${configName}-UTF16-CHANGED.csv`);

  lines.push(`OpenCC-Length-Diff-${configName}-SUMMARY.txt`);

  fs.writeFileSync(
    filePath,

    lines.join('\n') + '\n',

    'utf8',
  );

  console.log(`Created: ${fileName}`);
}

/* ============================================================
 * Main
 * ============================================================
 */

function main() {
  console.log('');

  console.log('OpenCC Length Difference Analyzer v3');

  console.log('=====================================');

  console.log(`Target opencc-js version: ${VERSION}`);

  console.log(`Output directory: ${OUTPUT_DIR}`);

  for (const configName of CONFIGS) {
    try {
      const results = analyzeConfig(configName);

      writeAllCsv(configName, results);

      writeChangedCsv(configName, results);

      writeSummary(configName, results);
    } catch (error) {
      console.error('');

      console.error(`ERROR while analyzing ${configName}`);

      console.error(error);

      /*
       * Do not immediately terminate.
       *
       * Try the other direction.
       */

      continue;
    }
  }

  console.log('');

  console.log('='.repeat(72));

  console.log('Analysis completed.');

  console.log('='.repeat(72));

  console.log('');
}

main();
