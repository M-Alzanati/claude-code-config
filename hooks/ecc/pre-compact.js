#!/usr/bin/env node
/**
 * PreCompact Hook - Save state before context compaction
 * Source: affaan-m/everything-claude-code (MIT)
 */

const path = require('path');
const {
  getSessionsDir, getProjectKey, getProjectSessionFile, getDateTimeString, getTimeString,
  ensurePrivateDir, appendPrivateFile, log
} = require('./lib/utils');

async function main() {
  const sessionsDir = getSessionsDir();
  const compactionLog = path.join(sessionsDir, `${getProjectKey()}-compaction.log`);

  ensurePrivateDir(sessionsDir);

  const timestamp = getDateTimeString();
  appendPrivateFile(compactionLog, `[${timestamp}] Context compaction triggered\n`);

  const activeSession = getProjectSessionFile();
  if (require('fs').existsSync(activeSession)) {
    const timeStr = getTimeString();
    appendPrivateFile(activeSession, `\n---\n**[Compaction occurred at ${timeStr}]** - Context was summarized\n`);
  }

  log('[PreCompact] State saved before compaction');
  process.exit(0);
}

main().catch(err => {
  console.error('[PreCompact] Error:', err.message);
  process.exit(0);
});
