#!/usr/bin/env node
/**
 * SessionStart Hook - Load previous session context on new session
 * Source: affaan-m/everything-claude-code (MIT), simplified
 */

const { getSessionsDir, getLearnedSkillsDir, findFiles, ensureDir, readFile, stripAnsi, log, output } = require('./lib/utils');

async function main() {
  const sessionsDir = getSessionsDir();
  const learnedDir = getLearnedSkillsDir();

  ensureDir(sessionsDir);
  ensureDir(learnedDir);

  // Inject the latest session summary (last 7 days) into context
  const recentSessions = findFiles(sessionsDir, '*-session.tmp', { maxAge: 7 });

  if (recentSessions.length > 0) {
    const latest = recentSessions[0];
    log(`[SessionStart] Found ${recentSessions.length} recent session(s), loading latest`);

    const content = stripAnsi(readFile(latest.path));
    if (content && !content.includes('[Session context goes here]')) {
      output(`Previous session summary:\n${content}`);
    }
  } else {
    log('[SessionStart] No recent sessions found');
  }

  // Report learned skills
  const learnedSkills = findFiles(learnedDir, '*.md');
  if (learnedSkills.length > 0) {
    log(`[SessionStart] ${learnedSkills.length} learned skill(s) available in ${learnedDir}`);
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[SessionStart] Error:', err.message);
  process.exit(0);
});
