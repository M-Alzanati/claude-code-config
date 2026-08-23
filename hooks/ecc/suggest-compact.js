#!/usr/bin/env node
/**
 * Strategic Compact Suggester - Suggests /compact at logical intervals
 * Source: affaan-m/everything-claude-code (MIT)
 *
 * Suggests manual compaction after COMPACT_THRESHOLD tool calls (default: 50)
 * then every 25 calls after that. Prevents auto-compact cutting in at bad times.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { getClaudeDir, openPrivateFile, log } = require('./lib/utils');

async function main() {
  const sessionId = (process.env.CLAUDE_SESSION_ID || 'default').replace(/[^a-zA-Z0-9_-]/g, '') || 'default';
  const counterDir = path.join(getClaudeDir(), 'private');
  const counterFile = path.join(counterDir, `tool-count-${crypto.createHash('sha256').update(sessionId).digest('hex')}`);
  const rawThreshold = parseInt(process.env.COMPACT_THRESHOLD || '50', 10);
  const threshold = Number.isFinite(rawThreshold) && rawThreshold > 0 && rawThreshold <= 10000 ? rawThreshold : 50;

  let count = 1;

  const fd = openPrivateFile(counterFile, fs.constants.O_RDWR | fs.constants.O_CREAT);
  try {
    const buf = Buffer.alloc(64);
    const bytesRead = fs.readSync(fd, buf, 0, 64, 0);
    if (bytesRead > 0) {
      const parsed = parseInt(buf.toString('utf8', 0, bytesRead).trim(), 10);
      count = (Number.isFinite(parsed) && parsed > 0 && parsed <= 1000000) ? parsed + 1 : 1;
    }
    fs.ftruncateSync(fd, 0);
    fs.writeSync(fd, String(count), 0);
  } finally {
    fs.closeSync(fd);
  }

  if (count === threshold) {
    log(`[StrategicCompact] ${threshold} tool calls reached — consider /compact if transitioning phases`);
  }

  if (count > threshold && (count - threshold) % 25 === 0) {
    log(`[StrategicCompact] ${count} tool calls — good checkpoint for /compact if context feels stale`);
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[StrategicCompact] Error:', err.message);
  process.exit(0);
});
