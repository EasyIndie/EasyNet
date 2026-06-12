# Contributing to EasyNet

Thank you for considering contributing to EasyNet! This project is open-source
and we welcome contributions of all kinds — bug reports, feature requests,
documentation improvements, and code changes.

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

---

## Table of Contents

- [How to Submit an Issue](#how-to-submit-an-issue)
- [Bug Fix Workflow](#bug-fix-workflow)
- [Feature Development Workflow](#feature-development-workflow)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Writing Tests](#writing-tests)
- [Code Conventions](#code-conventions)
- [Pull Request Process](#pull-request-process)
- [Code Review Checklist](#code-review-checklist)
- [Release Process](#release-process)

---

## How to Submit an Issue

Anyone can open an issue. Please choose the appropriate template when creating one:

- **Bug Report** — Something isn't working as expected. Please include your
  environment, EasyNet version, reproduction steps, and relevant log output.
- **Feature Request** — A new protocol, deployment option, or improvement.
  Describe the problem you're trying to solve and your proposed solution.
- **Question** — If you're unsure how something works, open a regular issue
  with the `question` label.

### After Submitting

A maintainer will triage the issue within **48 hours**. We may assign labels
(`bug`, `enhancement`, `question`, etc.) and ask for additional information.
If an issue lacks critical information and we receive no response for **14 days**,
it may be closed.

---

## Bug Fix Workflow

```
Bug Report → Triage → Fix Branch → PR → Review → Merge → Patch Release
```

1. **Report** — Open a Bug Report issue using the template.
2. **Triage** — A maintainer confirms the bug and assigns a severity:
   - **Critical** (service unavailable, data loss) → fixed immediately
   - **Normal** (functional issue, non-blocking) → next patch release
3. **Claim** — Comment `"I'll take this"` on the issue to avoid duplicate work.
4. **Branch** — Create a branch from `main`:
   ```bash
   git checkout -b fix/short-description
   # example: git checkout -b fix/singbox-dns-resolver
   ```
5. **Fix + Tests** — Implement the fix and add a regression test that covers it.
6. **PR** — Open a pull request. The PR description **must** include `Fixes #123`
   to link the issue (this also auto-closes it when merged).
7. **Review** — A maintainer reviews the fix.
8. **Merge** — The fix lands on `main`.
9. **Release** — The fix ships with the next patch release (e.g., `0.3.0` → `0.3.1`).

### Bug Fix PR Requirements

- PR title format: `fix: short description` (e.g., `fix: sing-box client DNS resolver`)
- Must link the issue: `Fixes #123` in the PR description
- Must include a regression test proving the bug is fixed and won't reappear
- All existing tests must pass

---

## Feature Development Workflow

```
Feature Request → Discussion → Feature Branch → PR → Review → Merge → Minor Release
```

1. **Request** — Open a Feature Request issue to discuss the proposal first.
2. **Consensus** — A maintainer confirms the direction and adds the
   `enhancement` label before work begins.
3. **Branch** — Create a branch from `main`:
   ```bash
   git checkout -b feature/short-description
   # example: git checkout -b feature/hysteria2-protocol
   ```
4. **Implement** — Write code, tests, and documentation (see the PR checklist
   below for what a new protocol must include).
5. **PR** — Open a pull request linking the feature request issue.
6. **Review** — A maintainer reviews the code.
7. **Merge** — The feature lands on `main`.
8. **Release** — The feature ships with the next minor release (e.g., `0.2.0` → `0.3.0`).

### New Protocol PR Must Include

```
scripts/protocols/<name>/
├── deploy.sh               # Deployment script
├── export.sh               # Configuration export
├── uninstall.sh            # Uninstall script
└── metadata.schema.json    # Metadata contract (optional but recommended)
tests/test_<name>_*.bash    # Corresponding test file(s)
docs/                       # Update deployment.md, clients.md as needed
```

For non-protocol changes (subscription system, edge gateway, CI, docs),
include what makes sense for the scope of the change.

---

## Development Setup

EasyNet is a pure Bash project. There is no build step.

### Prerequisites

```bash
# Install test dependencies
# Debian / Ubuntu:
sudo apt-get install -y jq ripgrep

# macOS:
brew install jq ripgrep
```

### Clone

```bash
git clone https://github.com/EasyIndie/EasyNet.git
cd EasyNet
```

---

## Running Tests

```bash
# Run the full test suite (13 test suites + shell syntax check)
bash tests/run_all_tests.bash

# Run a single test file (much faster during development)
bash tests/test_env_vars.bash
# The test runner auto-discovers all tests/test_*.bash files, but each
# file is also independently runnable.

# Verify shell syntax of all scripts (matches CI)
find scripts tests -type f \( -name "*.sh" -o -name "*.bash" \) \
  | sort | while IFS= read -r file; do bash -n "$file"; done
```

---

## Writing Tests

EasyNet uses a minimal custom Bash test framework defined in
[tests/test_helper.bash](tests/test_helper.bash).

### Test Framework API

```bash
source "$(dirname "$0")/test_helper.bash"

test_start "my test group name"

# Assert two values are equal
assert_equals "expected" "actual" "description of what is being tested"

# Assert a value is non-empty
assert_not_empty "$value" "description"

test_end
```

### Conventions

- Test files are named `test_<subject>.bash` and placed in `tests/`.
- They are auto-discovered by `run_all_tests.bash`. No registration needed.
- Each test file must be independently runnable (`bash test_foo.bash`).
- Tests may depend on `jq` and `ripgrep` being installed.

---

## Code Conventions

### Shell Style

- Use `#!/bin/bash` shebang
- Prefer `[[ ]]` over `[ ]` for conditionals
- Quote all variable expansions: `"$var"` not `$var`
- Use `local` for function-scoped variables
- Follow the existing naming and argument patterns in `scripts/core/`

### Logging

Use the shared logging library instead of raw `echo`:

```bash
source "$(dirname "$0")/../core/logging.sh"

log_info "Processing subscription for $profile"
log_warn "Certificate renewal skipped"
log_error "Failed to resolve domain: $domain"
```

### Syntax Check

All shell scripts must pass `bash -n`:

```bash
bash -n scripts/my-script.sh
```

### Hardcoding

Do not hardcode passwords, paths, or domain names. Use the metadata system
(`metadata.sh`) and environment variables instead.

---

## Pull Request Process

1. **Branch from `main`** and keep your branch up to date.
2. **Keep PRs focused** — one feature or fix per PR.
3. **Write or update tests** for your change.
4. **Run the full test suite** and confirm it passes.
5. **Update documentation** if your change affects usage.
6. **Link the issue** — use `Fixes #123` or `Refs #456` in the description.
7. **Wait for CI** — the Tests workflow runs automatically on your PR.
8. **Address review feedback** — make changes, push to the same branch, CI
   re-runs automatically.

---

## Code Review Checklist

Reviewers will check the following. You can pre-check these before submitting:

- [ ] Follows the existing project structure and patterns
- [ ] All shell files pass `bash -n` (syntax check)
- [ ] Core logic has corresponding test coverage
- [ ] Full test suite passes (`bash tests/run_all_tests.bash`)
- [ ] No hardcoded secrets, paths, or domain names
- [ ] Uses shared logging (`log_info` / `log_error`) instead of bare `echo`
- [ ] Documentation updated (`docs/`, README) if needed
- [ ] Bug fixes include a regression test
- [ ] PR description links the related issue (`Fixes #123`)

---

## Release Process

Releases follow [Semantic Versioning](https://semver.org/):

| Version bump | When                         | Example    |
|-------------|------------------------------|------------|
| PATCH       | Bug fixes, minor tweaks      | 0.3.0 → 0.3.1 |
| MINOR       | New features (backward compat) | 0.2.0 → 0.3.0 |
| MAJOR       | Breaking changes             | 1.0.0 → 2.0.0 |

### Maintainer Release Checklist

```bash
# 1. Ensure main is ready (all tests pass, changes merged)
# 2. Update VERSION file with the new version number
# 3. Update CHANGELOG.md (categorize changes under Added / Fixed / Changed)
# 4. Commit
git add VERSION CHANGELOG.md
git commit -m "Release X.Y.Z"
# 5. Push
git push origin main
# 6. Tag (semver only, no "v" prefix)
git tag X.Y.Z
git push origin X.Y.Z
# 7. GitHub Actions creates the release automatically
```

The [Release workflow](.github/workflows/release.yml) will:
1. Verify the VERSION file matches the git tag
2. Extract release notes from CHANGELOG.md
3. Create a GitHub Release

---

## Questions?

If you have questions about contributing, feel free to open a Discussion or an
issue with the `question` label.
