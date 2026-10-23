'use strict';

function sum(a, b) {
  if (!Number.isInteger(a) || !Number.isInteger(b)) {
    throw new TypeError('sum requires integer operands');
  }
  return a + b;
}

module.exports = sum;
