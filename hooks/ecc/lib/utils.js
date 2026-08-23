/**
 * Cross-platform utility functions for Claude Code hooks and scripts
 * Source: affaan-m/everything-claude-code (MIT)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawnSync } = require('child_process');

const isWindows = process.platform === 'win32';
const isMacOS = process.platform === 'darwin';
const isLinux = process.platform === 'linux';

function getHomeDir() { return os.homedir(); }
function getClaudeDir() { return path.join(getHomeDir(), '.claude'); }
function getSessionsDir() { return path.join(getClaudeDir(), 'sessions'); }
function getLearnedSkillsDir() { return path.join(getClaudeDir(), 'skills', 'learned'); }
function getTempDir() { return os.tmpdir(); }

function ensureDir(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
  } catch (err) {
    if (err.code !== 'EEXIST') throw new Error(`Failed to create directory '${dirPath}': ${err.message}`);
  }
  return dirPath;
}

function getDateString() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

function getTimeString() {
  const now = new Date();
  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}

function getDateTimeString() {
  const now = new Date();
  return `${getDateString()} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
}

function getGitRepoName() {
  const result = runCommand('git rev-parse --show-toplevel');
  if (!result.success) return null;
  return path.basename(result.output);
}

function getProjectName() {
  return getGitRepoName() || path.basename(process.cwd()) || null;
}

function getSessionIdShort(fallback = 'default') {
  const sessionId = process.env.CLAUDE_SESSION_ID;
  if (sessionId && sessionId.length > 0) return sessionId.slice(-8);
  return getProjectName() || fallback;
}

function findFiles(dir, pattern, options = {}) {
  if (!dir || !pattern || !fs.existsSync(dir)) return [];
  const { maxAge = null, recursive = false } = options;
  const results = [];
  const regexPattern = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
  const regex = new RegExp(`^${regexPattern}$`);

  function searchDir(currentDir) {
    try {
      const entries = fs.readdirSync(currentDir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(currentDir, entry.name);
        if (entry.isFile() && regex.test(entry.name)) {
          try {
            const stats = fs.statSync(fullPath);
            if (maxAge !== null) {
              const ageInDays = (Date.now() - stats.mtimeMs) / (1000 * 60 * 60 * 24);
              if (ageInDays <= maxAge) results.push({ path: fullPath, mtime: stats.mtimeMs });
            } else {
              results.push({ path: fullPath, mtime: stats.mtimeMs });
            }
          } catch { /* ignore */ }
        } else if (entry.isDirectory() && recursive) {
          searchDir(fullPath);
        }
      }
    } catch { /* ignore permission errors */ }
  }

  searchDir(dir);
  results.sort((a, b) => b.mtime - a.mtime);
  return results;
}

function readFile(filePath) {
  try { return fs.readFileSync(filePath, 'utf8'); } catch { return null; }
}

function writeFile(filePath, content) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, content, 'utf8');
}

function appendFile(filePath, content) {
  ensureDir(path.dirname(filePath));
  fs.appendFileSync(filePath, content, 'utf8');
}

function stripAnsi(str) {
  if (typeof str !== 'string') return '';
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1b(?:\[[0-9;?]*[A-Za-z]|\][^\x07\x1b]*(?:\x07|\x1b\\)|\([A-Z]|[A-Z])/g, '');
}

function log(message) { console.error(message); }
function output(data) {
  console.log(typeof data === 'object' ? JSON.stringify(data) : data);
}

function runCommand(cmd, options = {}) {
  const allowedPrefixes = ['git ', 'node ', 'npx ', 'which ', 'where '];
  if (!allowedPrefixes.some(prefix => cmd.startsWith(prefix))) {
    return { success: false, output: 'runCommand blocked: unrecognized command prefix' };
  }
  const unquoted = cmd.replace(/"[^"]*"/g, '').replace(/'[^']*'/g, '');
  if (/[;|&\n]/.test(unquoted) || /[`$]/.test(cmd)) {
    return { success: false, output: 'runCommand blocked: shell metacharacters not allowed' };
  }
  try {
    const result = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...options });
    return { success: true, output: result.trim() };
  } catch (err) {
    return { success: false, output: err.stderr || err.message };
  }
}

module.exports = {
  isWindows, isMacOS, isLinux,
  getHomeDir, getClaudeDir, getSessionsDir, getLearnedSkillsDir, getTempDir, ensureDir,
  getDateString, getTimeString, getDateTimeString,
  getSessionIdShort, getGitRepoName, getProjectName,
  findFiles, readFile, writeFile, appendFile, stripAnsi,
  log, output, runCommand,
};
