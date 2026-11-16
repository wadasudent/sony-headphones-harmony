const fs = require('node:fs');
const path = require('node:path');

// DevEco ships Node under tools/node (or tools/node/bin) alongside its SDK.
const executableDir = path.dirname(process.execPath);
const nodeHome = path.basename(executableDir) === 'bin' ? path.dirname(executableDir) : executableDir;
const sdkHome = process.env.DEVECO_SDK_HOME || path.resolve(nodeHome, '../../sdk');
const compiler = path.join(sdkHome, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
if (!fs.existsSync(compiler)) {
  throw new Error('Set DEVECO_SDK_HOME to the installed HarmonyOS SDK directory, or run build.ps1 -CheckOnly.');
}
module.exports = require(compiler);
