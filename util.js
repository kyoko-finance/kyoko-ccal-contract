const fs = require('fs');
const path = require('path');

module.exports = function(data, fileName) {
    const existDataStr = fs.readFileSync(path.resolve(__dirname, `./${fileName}`), { flag: 'a+', encoding: 'utf8' }, console.error);

    const existData = JSON.parse(existDataStr || '{}');

    fs.writeFileSync(path.resolve(__dirname, `./${fileName}`), JSON.stringify({ ...existData, ...data }, null, 4), { flag: 'w', encoding: 'utf-8' }, console.error);
}
