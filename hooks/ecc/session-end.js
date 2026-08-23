#!/usr/bin/env node
/**
 * Stop Hook (Session End) - Persist session summary across sessions
 * Source: affaan-m/everything-claude-code (MIT)
 */

const path = require('path');
const fs = require('fs');
const {
  getSessionsDir, getDateString, getTimeString, getProjectKey, getProjectSessionFile,
  getProjectRoot, getProjectName, ensurePrivateDir, readFile, writePrivateFile, runCommand, stripAnsi, log
} = require('./lib/utils');

const METADATA_START_MARKER = '<!-- ECC:SESSION-METADATA:v1 -->';
const METADATA_END_MARKER = '<!-- ECC:SESSION-METADATA:END -->';
const MAX_PATH_LENGTH = 240;

function extractSessionSummary(transcriptPath) {
  const content = readFile(transcriptPath);
  if (!content) return null;

  const lines = content.split('\n').filter(Boolean);
  const toolsUsed = new Set();
  const filesModified = new Set();
  let userMessageCount = 0;
  const projectRoot = getProjectRoot();

  const addTool = (toolName, filePath) => {
    const tool = typeof toolName === 'string' ? stripAnsi(toolName).replace(/[\x00-\x1f\x7f]/g, '').slice(0, 80) : '';
    if (tool) toolsUsed.add(tool);
    if ((tool === 'Edit' || tool === 'Write') && typeof filePath === 'string') {
      const absolute = path.resolve(projectRoot, filePath);
      const relative = path.relative(projectRoot, absolute);
      if (relative && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative)) {
        filesModified.add(relative.split(path.sep).join('/').slice(0, MAX_PATH_LENGTH));
      }
    }
  };

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);

      if (entry.type === 'user' || entry.role === 'user' || entry.message?.role === 'user') {
        userMessageCount += 1;
      }

      if (entry.type === 'tool_use' || entry.tool_name) {
        addTool(entry.tool_name || entry.name || '', entry.tool_input?.file_path || entry.input?.file_path || '');
      }

      if (entry.type === 'assistant' && Array.isArray(entry.message?.content)) {
        for (const block of entry.message.content) {
          if (block.type === 'tool_use') {
            addTool(block.name || '', block.input?.file_path || '');
          }
        }
      }
    } catch { /* skip unparseable lines */ }
  }

  return {
    userMessageCount,
    toolsUsed: Array.from(toolsUsed).slice(0, 20),
    filesModified: Array.from(filesModified).slice(0, 30),
  };
}

function buildSessionHeader(today, currentTime, metadata) {
  return [
    `# Session: ${today}`,
    `**Date:** ${today}`,
    `**Started:** ${currentTime}`,
    `**Last Updated:** ${currentTime}`,
    `**Project:** ${metadata.project}`,
    `**Branch:** ${metadata.branch}`,
    '',
  ].join('\n');
}

function buildMetadataBlock(summary, metadata) {
  return `${METADATA_START_MARKER}\n${JSON.stringify({
    version: 1,
    projectKey: metadata.projectKey,
    project: metadata.project,
    branch: metadata.branch,
    userMessageCount: summary.userMessageCount,
    toolsUsed: summary.toolsUsed,
    filesModified: summary.filesModified,
  })}\n${METADATA_END_MARKER}`;
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
  const sessionFile = getProjectSessionFile();
  const branchResult = runCommand('git rev-parse --abbrev-ref HEAD');

  const metadata = {
    projectKey: getProjectKey(),
    project: (getProjectName() || 'unknown').replace(/[\x00-\x1f\x7f]/g, '').slice(0, 120),
    branch: (branchResult.success ? branchResult.output : 'unknown').replace(/[\x00-\x1f\x7f]/g, '').slice(0, 120),
  };

  ensurePrivateDir(sessionsDir);

  const currentTime = getTimeString();
  let summary = null;

  if (transcriptPath && fs.existsSync(transcriptPath)) summary = extractSessionSummary(transcriptPath);
  if (!summary) summary = { userMessageCount: 0, toolsUsed: [], filesModified: [] };

  const header = buildSessionHeader(today, currentTime, metadata);
  const content = `${header}\n---\n${buildMetadataBlock(summary, metadata)}\n`;
  writePrivateFile(sessionFile, content);
  log(`[SessionEnd] Saved project session metadata: ${sessionFile}`);

  process.exit(0);
}
