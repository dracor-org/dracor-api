#!/bin/env node

// node sign.js secret datafile

const fs = require('fs');
const crypto = require('crypto');

const secret = process.argv[2]
const file = process.argv[3]

const payload = fs.readFileSync(file, 'utf8');


const hash = crypto.createHmac('sha1', secret)
                   .update(payload)
                   .digest('hex');

console.log(`sha1=${hash}`);
