#!/usr/bin/env node
/**
 * Stop Hook (Session End) - Persist session summary across sessions
 * Source: affaan-m/everything-claude-code (MIT)
 */

const path = require('path');
const fs = require('fs');
const {
  getSessionsDir, getDateString, getTimeString, getSessionIdShort, getProjectName,
  ensureDir, readFile, writeFile, appendFile, runCommand, stripAnsi, log
} = require('./lib/utils');

const SUMMARY_START_MARKER = '<!-- ECC:SUMMARY:START -->';
const SUMMARY_END_MARKER = '<!-- ECC:SUMMARY:END -->';
const SESSION_SEPARATOR = '\n---\n';

function extractSessionSummary(transcriptPath) {
  const content = readFile(transcriptPath);
  if (!content) return null;

  const lines = content.split('\n').filter(Boolean);
  const userMessages = [];
  const toolsUsed = new Set();
  const filesModified = new Set();

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);

      if (entry.type === 'user' || entry.role === 'user' || entry.message?.role === 'user') {
        const rawContent = entry.message?.content ?? entry.content;
        const text = typeof rawContent === 'string'
          ? rawContent
          : Array.isArray(rawContent) ? rawContent.map(c => (c && c.text) || '').join(' ') : '';
        const cleaned = stripAnsi(text).trim();
        if (cleaned) userMessages.push(cleaned.slice(0, 200));
      }

      if (entry.type === 'tool_use' || entry.tool_name) {
        const toolName = entry.tool_name || entry.name || '';
        if (toolName) toolsUsed.add(toolName);
        const filePath = entry.tool_input?.file_path || entry.input?.file_path || '';
        if (filePath && (toolName === 'Edit' || toolName === 'Write')) filesModified.add(filePath);
      }

      if (entry.type === 'assistant' && Array.isArray(entry.message?.content)) {
        for (const block of entry.message.content) {
          if (block.type === 'tool_use') {
            const toolName = block.name || '';
            if (toolName) toolsUsed.add(toolName);
            const filePath = block.input?.file_path || '';
            if (filePath && (toolName === 'Edit' || toolName === 'Write')) filesModified.add(filePath);
          }
        }
      }
    } catch { /* skip unparseable lines */ }
  }

  if (userMessages.length === 0) return null;

  return {
    userMessages: userMessages.slice(-10),
    toolsUsed: Array.from(toolsUsed).slice(0, 20),
    filesModified: Array.from(filesModified).slice(0, 30),
    totalMessages: userMessages.length,
  };
}

function buildSessionHeader(today, currentTime, metadata, existingContent = '') {
  const headingMatch = existingContent.match(/^#\s+.+$/m);
  const heading = headingMatch ? headingMatch[0] : `# Session: ${today}`;
  const dateMatch = existingContent.match(/\*\*Date:\*\*\s*(.+)$/m);
  const startedMatch = existingContent.match(/\*\*Started:\*\*\s*(.+)$/m);
  const date = dateMatch ? dateMatch[1].trim() : today;
  const started = startedMatch ? startedMatch[1].trim() : currentTime;

  return [
    heading,
    `**Date:** ${date}`,
    `**Started:** ${started}`,
    `**Last Updated:** ${currentTime}`,
    `**Project:** ${metadata.project}`,
    `**Branch:** ${metadata.branch}`,
    '',
  ].join('\n');
}

function buildSummarySection(summary) {
  let section = '## Session Summary\n\n### Tasks\n';
  for (const msg of summary.userMessages) {
    section += `- ${msg.replace(/\n/g, ' ').replace(/`/g, '\\`')}\n`;
  }
  section += '\n';
  if (summary.filesModified.length > 0) {
    section += '### Files Modified\n';
    for (const f of summary.filesModified) section += `- ${f}\n`;
    section += '\n';
  }
  if (summary.toolsUsed.length > 0) {
    section += `### Tools Used\n${summary.toolsUsed.join(', ')}\n\n`;
  }
  section += `### Stats\n- Total user messages: ${summary.totalMessages}\n`;
  return section;
}

function buildSummaryBlock(summary) {
  return `${SUMMARY_START_MARKER}\n${buildSummarySection(summary).trim()}\n${SUMMARY_END_MARKER}`;
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Read stdin for transcript_path
const MAX_STDIN = 1024 * 1024;
let stdinData = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  if (stdinData.length < MAX_STDIN) stdinData += chunk.substring(0, MAX_STDIN - stdinData.length);
});
process.stdin.on('end', () => {
  main().catch(err => {
    console.error('[SessionEnd] Error:', err.message);
    process.exit(0);
  });
});

async function main() {
  let transcriptPath = null;
  try {
    const input = JSON.parse(stdinData);
    transcriptPath = input.transcript_path;
  } catch {
    transcriptPath = process.env.CLAUDE_TRANSCRIPT_PATH;
  }

  const sessionsDir = getSessionsDir();
  const today = getDateString();
  const shortId = getSessionIdShort();
  const sessionFile = path.join(sessionsDir, `${today}-${shortId}-session.tmp`);
  const branchResult = runCommand('git rev-parse --abbrev-ref HEAD');

  const metadata = {
    project: getProjectName() || 'unknown',
    branch: branchResult.success ? branchResult.output : 'unknown',
  };

  ensureDir(sessionsDir);

  const currentTime = getTimeString();
  let summary = null;

  if (transcriptPath && fs.existsSync(transcriptPath)) {
    summary = extractSessionSummary(transcriptPath);
  }

  if (fs.existsSync(sessionFile)) {
    let content = readFile(sessionFile);
    if (content) {
      // Update header timestamps
      const sepIdx = content.indexOf(SESSION_SEPARATOR);
      if (sepIdx !== -1) {
        const existingHeader = content.slice(0, sepIdx);
        const body = content.slice(sepIdx + SESSION_SEPARATOR.length);
        const newHeader = buildSessionHeader(today, currentTime, metadata, existingHeader);
        content = `${newHeader}${SESSION_SEPARATOR}${body}`;
      }

      // Update summary block
      if (summary) {
        const summaryBlock = buildSummaryBlock(summary);
        if (content.includes(SUMMARY_START_MARKER) && content.includes(SUMMARY_END_MARKER)) {
          content = content.replace(
            new RegExp(`${escapeRegExp(SUMMARY_START_MARKER)}[\\s\\S]*?${escapeRegExp(SUMMARY_END_MARKER)}`),
            summaryBlock
          );
        } else {
          content += `\n\n${summaryBlock}`;
        }
      }

      writeFile(sessionFile, content);
      log(`[SessionEnd] Updated session file: ${sessionFile}`);
    }
  } else {
    const summarySection = summary
      ? `${buildSummaryBlock(summary)}\n\n### Notes for Next Session\n-\n\n### Context to Load\n\`\`\`\n[relevant files]\n\`\`\``
      : `## Current State\n\n[Session context goes here]\n\n### Completed\n- [ ]\n\n### In Progress\n- [ ]\n\n### Notes for Next Session\n-\n\n### Context to Load\n\`\`\`\n[relevant files]\n\`\`\``;

    const header = buildSessionHeader(today, currentTime, metadata);
    writeFile(sessionFile, `${header}${SESSION_SEPARATOR}${summarySection}\n`);
    log(`[SessionEnd] Created session file: ${sessionFile}`);
  }

  process.exit(0);
}
