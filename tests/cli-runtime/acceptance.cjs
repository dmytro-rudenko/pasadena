'use strict';

const assert = require('node:assert/strict');

const invalidInputs = [
  ['fraction', 1.5],
  ['NaN', NaN],
  ['positive infinity', Infinity],
  ['negative infinity', -Infinity],
  ['string', '2'],
  ['null', null],
  ['undefined', undefined],
  ['true', true],
  ['false', false],
  ['object', {}],
  ['BigInt', 2n],
];

function loadFunction(name) {
  let exported;
  assert.doesNotThrow(() => {
    exported = require(`./${name}.js`);
  }, `${name}: production module must exist and load`);
  assert.equal(typeof exported, 'function', `${name}: direct function export`);
  return exported;
}

const suites = {
  sum() {
    const sum = loadFunction('sum');
    for (const [a, b, expected] of [
      [2, 3, 5],
      [-2, -3, -5],
      [-2, 3, 1],
      [0, 0, 0],
      [0, 7, 7],
      [7, 0, 7],
      [Number.MAX_SAFE_INTEGER + 1, 2, Number.MAX_SAFE_INTEGER + 3],
      [Number.MAX_VALUE, Number.MAX_VALUE, Infinity],
    ]) {
      assert.equal(sum(a, b), expected, `sum(${a}, ${b})`);
    }
    for (const [label, value] of invalidInputs) {
      assert.throws(() => sum(value, 2), TypeError, `sum rejects ${label} first operand`);
      assert.throws(() => sum(2, value), TypeError, `sum rejects ${label} second operand`);
    }
  },
  double() {
    const double = loadFunction('double');
    for (const [n, expected] of [
      [3, 6],
      [-3, -6],
      [0, 0],
      [Number.MAX_SAFE_INTEGER + 1, 18014398509481984],
      [Number.MAX_VALUE, Infinity],
    ]) {
      assert.equal(double(n), expected, `double(${n})`);
    }
    for (const [label, value] of invalidInputs) {
      assert.throws(() => double(value), TypeError, `double rejects ${label}`);
    }
  },
};

const args = process.argv.slice(2);
if (args.length > 1 || (args.length === 1 && !Object.hasOwn(suites, args[0]))) {
  console.error('Usage: node tests/cli-runtime/acceptance.cjs [sum|double]');
  process.exitCode = 1;
} else {
  const selected = args.length === 0 ? Object.keys(suites) : args;
  let failures = 0;
  for (const name of selected) {
    try {
      suites[name]();
      console.log(`PASS ${name}`);
    } catch (error) {
      failures += 1;
      console.error(`FAIL ${name}: ${error.name}: ${error.message}`);
    }
  }
  if (failures > 0) {
    console.error(`FAILED: ${failures} suite(s)`);
    process.exitCode = 1;
  } else {
    console.log('All checks passed.');
  }
}
