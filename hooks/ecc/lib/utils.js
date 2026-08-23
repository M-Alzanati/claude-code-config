/**
 * Cross-platform utility functions for Claude Code hooks and scripts
 * Source: affaan-m/everything-claude-code (MIT)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execSync, spawnSync } = require('child_process');

const isWindows = process.platform === 'win32';
const isMacOS = process.platform === 'darwin';
const isLinux = process.platform === 'linux';

function getHomeDir() { return os.homedir(); }
function getClaudeDir() { return process.env.CLAUDE_CONFIG_DIR || path.join(getHomeDir(), '.claude'); }
function getSessionsDir() { return path.join(getClaudeDir(), 'sessions'); }
function getLearnedSkillsDir() { return path.join(getClaudeDir(), 'skills', 'learned'); }
function getTempDir() { return os.tmpdir(); }

function getProjectRoot() {
  const result = runCommand('git rev-parse --show-toplevel');
  const candidate = result.success && result.output ? result.output : process.cwd();
  try { return fs.realpathSync(candidate); } catch { return path.resolve(candidate); }
}

function getGitIdentity(root = getProjectRoot()) {
  const gitDirResult = runCommand('git rev-parse --git-dir');
  const rootCommitResult = runCommand('git rev-list --max-parents=0 HEAD');
  const gitDir = gitDirResult.success && gitDirResult.output
    ? path.resolve(root, gitDirResult.output)
    : '';
  let canonicalGitDir = gitDir;
  try { canonicalGitDir = fs.realpathSync(gitDir); } catch { /* repository may not have a worktree yet */ }
  return `${canonicalGitDir}\n${rootCommitResult.success ? rootCommitResult.output : 'unborn'}`;
}

function getProjectKey() {
  const root = getProjectRoot();
  return crypto.createHash('sha256').update(`${root}\n${getGitIdentity(root)}`).digest('hex');
}

function getProjectSessionFile() {
  return path.join(getSessionsDir(), `${getProjectKey()}-session.tmp`);
}

function ensureDir(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
  } catch (err) {
    if (err.code !== 'EEXIST') throw new Error(`Failed to create directory '${dirPath}': ${err.message}`);
  }
  return dirPath;
}

function ensurePrivateDir(dirPath) {
  let stats;
  try {
    stats = fs.lstatSync(dirPath);
    if (stats.isSymbolicLink() || !stats.isDirectory()) throw new Error(`Private directory is not a directory: '${dirPath}'`);
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
    fs.mkdirSync(dirPath, { recursive: true, mode: 0o700 });
    stats = fs.lstatSync(dirPath);
    if (stats.isSymbolicLink() || !stats.isDirectory()) throw new Error(`Private directory is not a directory: '${dirPath}'`);
  }
  fs.chmodSync(dirPath, 0o700);
  return dirPath;
}

function openPrivateFile(filePath, flags) {
  ensurePrivateDir(path.dirname(filePath));
  try {
    const stats = fs.lstatSync(filePath);
    if (stats.isSymbolicLink() || !stats.isFile()) throw new Error(`Private file is not a regular file: '${filePath}'`);
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
  }
  const noFollow = fs.constants.O_NOFOLLOW || 0;
  const fd = fs.openSync(filePath, flags | noFollow, 0o600);
  fs.fchmodSync(fd, 0o600);
  return fd;
}

function readPrivateFile(filePath) {
  let fd;
  try {
    fd = openPrivateFile(filePath, fs.constants.O_RDONLY);
    return fs.readFileSync(fd, 'utf8');
  } catch {
    return null;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

function writePrivateFile(filePath, content) {
  const fd = openPrivateFile(filePath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC);
  try { fs.writeFileSync(fd, content, 'utf8'); } finally { fs.closeSync(fd); }
}

function appendPrivateFile(filePath, content) {
  const fd = openPrivateFile(filePath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_APPEND);
  try { fs.writeFileSync(fd, content, 'utf8'); } finally { fs.closeSync(fd); }
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
  getHomeDir, getClaudeDir, getSessionsDir, getLearnedSkillsDir, getTempDir,
  getProjectRoot, getGitIdentity, getProjectKey, getProjectSessionFile, ensureDir, ensurePrivateDir,
  openPrivateFile, readPrivateFile, writePrivateFile, appendPrivateFile,
  getDateString, getTimeString, getDateTimeString,
  getSessionIdShort, getGitRepoName, getProjectName,
  findFiles, readFile, writeFile, appendFile, stripAnsi,
  log, output, runCommand,
};
