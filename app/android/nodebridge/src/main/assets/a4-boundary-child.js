'use strict';

if (typeof process.send === 'function') process.send('a4-boundary-child-ready');
setTimeout(() => process.exit(0), 100);
