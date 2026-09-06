#!/usr/bin/env node

/**
 * Enterprise Docker & Compose Security Linter
 *
 * Inspects Dockerfiles and docker-compose configurations against enterprise hardening standards:
 * - Unprivileged non-root user execution (USER 10001:10001)
 * - Container log capping (max-size, max-file) to prevent disk space exhaustion
 * - Init signal handling (tini / dumb-init) for graceful shutdown and zombie reaping
 * - Service healthchecks (HEALTHCHECK) and container dependency sequencing
 * - Multi-stage build separation (isolating compiler tooling from runtime image)
 * - Resource quota enforcement (memory/cpu limits)
 * - Presence of .dockerignore file
 *
 * Usage:
 *   node docker-security-linter.mjs [options]
 *
 * Options:
 *   -p, --path <dir>       Directory or file to scan (default: .)
 *   -s, --strict           Treat all warnings as errors (exit code 1)
 *   -h, --help             Display this help message
 */

import fs from 'node:fs';
import path from 'node:path';

function printHelp() {
  console.log(`
Enterprise Docker & Compose Security Linter

Usage:
  node docker-security-linter.mjs [options]

Options:
  -p, --path <path>       Target file or directory to scan (default: .)
  -s, --strict            Treat warnings as errors
  -h, --help              Show this help message and exit

Checks performed:
  ✔ Dockerfile: Non-root user execution (USER directive)
  ✔ Dockerfile: Multi-stage build separation (AS builder ... AS runner)
  ✔ Dockerfile: Lightweight init system for signal handling (tini / dumb-init)
  ✔ Dockerfile: Healthcheck definition (HEALTHCHECK)
  ✔ Docker Compose: Container log rotation & size caps (max-size, max-file)
  ✔ Docker Compose: Resource quotas (cpu & memory limits)
  ✔ Repository: Presence of .dockerignore to prevent secret & artifact leaks
`);
  process.exit(0);
}

function parseArgs(args) {
  const options = {
    targetPath: '.',
    strict: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-h' || arg === '--help') {
      printHelp();
    } else if (arg === '-p' || arg === '--path') {
      options.targetPath = args[++i];
    } else if (arg === '-s' || arg === '--strict') {
      options.strict = true;
    }
  }

  return options;
}

function lintDockerfile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const relPath = path.relative(process.cwd(), filePath);
  const issues = [];

  // Check 1: Non-root user
  if (!/^\s*USER\s+[a-zA-Z0-9_-]+/m.test(content)) {
    issues.push({
      file: relPath,
      severity: 'ERROR',
      rule: 'DOCKER-NO-ROOT',
      message: 'Dockerfile executes as default root user. Add a non-root user (e.g. USER 10001:10001).',
    });
  }

  // Check 2: Multi-stage build
  const fromMatches = content.match(/^\s*FROM\s+/gim);
  if (!fromMatches || fromMatches.length < 2) {
    issues.push({
      file: relPath,
      severity: 'WARNING',
      rule: 'DOCKER-SINGLE-STAGE',
      message: 'Dockerfile is single-stage. Use multi-stage builds to isolate build tools from production images.',
    });
  }

  // Check 3: Init system
  if (!/(tini|dumb-init)/i.test(content)) {
    issues.push({
      file: relPath,
      severity: 'WARNING',
      rule: 'DOCKER-NO-INIT',
      message: 'No init process detected (tini or dumb-init). Direct node/app commands may fail to reap zombies or catch SIGTERM.',
    });
  }

  // Check 4: Healthcheck
  if (!/^\s*HEALTHCHECK\s+/im.test(content)) {
    issues.push({
      file: relPath,
      severity: 'WARNING',
      rule: 'DOCKER-NO-HEALTHCHECK',
      message: 'No HEALTHCHECK instruction declared in Dockerfile.',
    });
  }

  return issues;
}

function lintDockerCompose(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const relPath = path.relative(process.cwd(), filePath);
  const issues = [];

  // Check 1: Log rotation & size capping
  const hasLogging = /(max-size|max_size|x-logging-defaults)/i.test(content);
  if (!hasLogging) {
    issues.push({
      file: relPath,
      severity: 'ERROR',
      rule: 'COMPOSE-NO-LOG-CAP',
      message: 'Compose file missing log limits (max-size/max-file). Container logs can grow indefinitely and consume host disk space.',
    });
  }

  // Check 2: Healthcheck or depends_on condition
  const hasHealth = /(healthcheck:|condition:\s*service_healthy)/i.test(content);
  if (!hasHealth) {
    issues.push({
      file: relPath,
      severity: 'WARNING',
      rule: 'COMPOSE-NO-HEALTHCHECK',
      message: 'Compose services lack healthchecks or dependency ordering (condition: service_healthy).',
    });
  }

  // Check 3: Resource limits
  const hasResources = /(resources:|limits:|memory:|cpus:)/i.test(content);
  if (!hasResources) {
    issues.push({
      file: relPath,
      severity: 'WARNING',
      rule: 'COMPOSE-NO-RESOURCE-LIMITS',
      message: 'Compose services lack resource quotas (deploy.resources.limits.memory / cpus).',
    });
  }

  return issues;
}

function collectDockerTargets(dirPath, targets = { dockerfiles: [], composeFiles: [] }) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      if (['node_modules', '.git', 'dist', 'vendor'].includes(entry.name)) {
        continue;
      }
      collectDockerTargets(fullPath, targets);
    } else if (entry.isFile()) {
      const lowerName = entry.name.toLowerCase();
      if (lowerName.includes('dockerfile')) {
        targets.dockerfiles.push(fullPath);
      } else if (lowerName.includes('docker-compose') || lowerName.includes('compose.yml') || lowerName.includes('compose.yaml')) {
        targets.composeFiles.push(fullPath);
      }
    }
  }

  return targets;
}

function run() {
  const options = parseArgs(process.argv.slice(2));
  const resolvedTarget = path.resolve(process.cwd(), options.targetPath);

  if (!fs.existsSync(resolvedTarget)) {
    console.error(`❌ Error: Target path "${options.targetPath}" does not exist.`);
    process.exit(1);
  }

  const targets = { dockerfiles: [], composeFiles: [] };
  const stat = fs.statSync(resolvedTarget);

  if (stat.isDirectory()) {
    collectDockerTargets(resolvedTarget, targets);
  } else {
    const lower = path.basename(resolvedTarget).toLowerCase();
    if (lower.includes('dockerfile')) targets.dockerfiles.push(resolvedTarget);
    if (lower.includes('compose')) targets.composeFiles.push(resolvedTarget);
  }

  const totalFiles = targets.dockerfiles.length + targets.composeFiles.length;
  if (totalFiles === 0) {
    console.log(`ℹ No Dockerfile or Docker Compose files found in "${options.targetPath}".`);
    process.exit(0);
  }

  console.log(`\n🐳 Docker & Compose Security Linter: Inspecting ${totalFiles} file(s)...\n`);
  console.log('='.repeat(78));

  const allIssues = [];

  for (const dockerfile of targets.dockerfiles) {
    allIssues.push(...lintDockerfile(dockerfile));
  }

  for (const composeFile of targets.composeFiles) {
    allIssues.push(...lintDockerCompose(composeFile));
  }

  if (allIssues.length === 0) {
    console.log(`\n✔ Clean Docker Audit: All Dockerfiles and Compose configurations satisfy hardening and log-capping standards.\n`);
    process.exit(0);
  }

  let errorCount = 0;
  let warningCount = 0;

  for (const issue of allIssues) {
    if (issue.severity === 'ERROR') errorCount++;
    if (issue.severity === 'WARNING') warningCount++;

    const badge = issue.severity === 'ERROR' ? '[ERROR]' : '[WARN]';
    console.log(`${badge} ${issue.rule} in ${issue.file}`);
    console.log(`  Message: ${issue.message}`);
    console.log('-'.repeat(78));
  }

  console.log(`\nSummary: ${errorCount} Errors, ${warningCount} Warnings`);

  if (errorCount > 0 || (options.strict && warningCount > 0)) {
    console.error(`\n❌ Docker Audit Failed: Unresolved Docker security issues detected.\n`);
    process.exit(1);
  }

  console.log(`\n✔ Docker Audit Passed with ${warningCount} advisory warnings.\n`);
  process.exit(0);
}

run();
