'use strict';

function double(n) {
  if (!Number.isInteger(n)) {
    throw new TypeError('double requires an integer');
  }
  return n * 2;
}

module.exports = double;
