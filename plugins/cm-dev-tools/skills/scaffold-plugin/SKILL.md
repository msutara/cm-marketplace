---
name: scaffold-plugin
description: >
  Create a new Config Manager plugin repository with full boilerplate — Go module,
  CI workflows, specs, docs, issue templates, and core wiring. Scaffolds the plugin
  struct implementing plugin.Plugin (and optionally plugin.Configurable), service
  layer, Chi routes, httptest-based tests, and an initial PR on phase1/skeleton-and-specs.
  USE FOR: create plugin, new plugin, scaffold plugin, add plugin repo, new cm plugin,
  plugin skeleton, create cm plugin, bootstrap plugin.
---

# Scaffold CM Plugin

One-shot creation of a fully wired Config Manager plugin repository. After this
skill completes you will have a public GitHub repo, passing CI, an initial PR,
and the plugin registered in the core binary.

## Project Context

Read project context from `.cm/project.json` if available. Discovery order:
`$CM_REPO_BASE` → cwd → parent directory → `$HOME/repo`. If no manifest is found,
ask the user for the required values before proceeding.

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  jq '.' "$_cm"
else
  echo "No manifest found — ask the user for owner, repo names, and other context."
fi
```

Use `reference_repo` for the reference repository and `owner` for the GitHub owner.
Use `project_board.id` for the project board ID.

## Step 0 — Gather Input

If any of these values were **not** provided by the user, ask before proceeding.

| Parameter | Example | Required |
| --- | --- | --- |
| **Plugin name** (lowercase, `^[a-z][a-z0-9-]*$`) | `firewall` | yes |
| **Short description** | Manages iptables/nftables firewall rules | yes |
| **Needs scheduled jobs?** (bool) | `true` | yes |
| **Needs config sections?** (bool — implements `plugin.Configurable`) | `true` | yes |
| **Initial endpoints** (method, path, description) | `GET /status`, `POST /apply` | yes |

Derive from these:

- **Go package name** — same as plugin name, but replace hyphens with underscores
  if the name contains hyphens (Go packages cannot have hyphens). For single-word
  names like `firewall`, the package name is `firewall`.
- **Repo name** — `cm-plugin-{name}`
- **Module path** — `github.com/{OWNER}/cm-plugin-{name}`
- **Constructor** — `New{Name}Plugin()` (PascalCase)
- **Struct** — `{Name}Plugin` (PascalCase)

## Step 1 — Create the GitHub Repository

```bash
gh repo create {OWNER}/cm-plugin-{name} --public --clone --description "{description}"
cd cm-plugin-{name} || { echo "Failed to cd into cm-plugin-{name}"; exit 1; }
git checkout -b phase1/skeleton-and-specs
```

Verify the repo was created:

```bash
gh repo view {OWNER}/cm-plugin-{name} --json name,url
```

## Step 2 — Generate the Directory Tree

The final layout must be:

```txt
cm-plugin-{name}/
├── go.mod
├── go.sum
├── plugin.go
├── service.go
├── routes.go
├── plugin_test.go
├── service_test.go
├── routes_test.go
├── specs/
│   ├── SPEC.md
│   └── ARCHITECTURE.md
├── docs/
│   └── USAGE.md
├── .github/
│   ├── copilot-instructions.md
│   ├── dependabot.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── config.yml
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── .golangci.yml
├── .markdownlint.json
├── .gitignore
├── LICENSE
├── README.md
└── CONTRIBUTING.md
```

Create each file using the templates below. Replace every `{name}`, `{Name}`,
`{description}`, and `{pkg}` placeholder with the derived values.

## Step 3 — File Templates

### 3.1 — go.mod

```go
module github.com/{OWNER}/cm-plugin-{name}

go 1.24.0

require github.com/go-chi/chi/v5 v5.2.5

require github.com/{OWNER}/config-manager-core v0.0.0
```

Before running `go mod tidy`, replace the placeholder `v0.0.0` with the latest
tag from `config-manager-core` (the core dependency all plugins import):

```bash
_ver=$(git -C "$CM_REPO_BASE/config-manager-core" describe --tags --abbrev=0)
sed -i.bak "s|config-manager-core v0.0.0|config-manager-core $_ver|" go.mod && rm -f go.mod.bak
```

After writing the file, run:

```bash
go mod tidy
```

### 3.2 — plugin.go

```go
// Package {pkg} implements the {name} plugin for Config Manager.
package {pkg}

import (
	"net/http"
	"sync"

	"github.com/{OWNER}/config-manager-core/plugin"
)

// Compile-time interface checks.
var _ plugin.Plugin = (*{Name}Plugin)(nil)
// CONDITIONAL: include the next line only if Configurable is needed.
var _ plugin.Configurable = (*{Name}Plugin)(nil)

// version is set at build time via ldflags:
//
//	-X github.com/{OWNER}/cm-plugin-{name}.version=<version>
var version = "dev"

// {Name}Plugin implements plugin.Plugin for {description}.
type {Name}Plugin struct {
	svc *Service
	mu  sync.RWMutex

	// CONDITIONAL: add config fields here if Configurable is needed.
	// Example:
	// schedule string
}

// New{Name}Plugin creates a new {Name}Plugin with default settings.
func New{Name}Plugin() *{Name}Plugin {
	svc := &Service{}
	return &{Name}Plugin{
		svc: svc,
	}
}

func (p *{Name}Plugin) Name() string {
	return "{name}"
}

func (p *{Name}Plugin) Version() string {
	return version
}

func (p *{Name}Plugin) Description() string {
	return "{description}"
}

func (p *{Name}Plugin) Routes() http.Handler {
	// CONDITIONAL: if Configurable, pass p.CurrentConfig as second arg
	return newRouter(p.svc)
}

func (p *{Name}Plugin) ScheduledJobs() []plugin.JobDefinition {
	// CONDITIONAL: if needs_jobs is false, return nil.
	// If true, return job definitions. Example:
	// return []plugin.JobDefinition{
	//  {
	//   ID:          "{name}.check",
	//   Description: "Periodic {name} check",
	//   Cron:        "0 * * * *",
	//   Func:        p.svc.RunCheck,
	//  },
	// }
	return nil
}

func (p *{Name}Plugin) Endpoints() []plugin.Endpoint {
	return []plugin.Endpoint{
		// FILL: one entry per endpoint from the user's initial endpoints list.
		// Example:
		// {Method: "GET", Path: "/status", Description: "Current {name} status"},
		// {Method: "POST", Path: "/apply", Description: "Apply {name} rules"},
	}
}

// --- Configurable interface (CONDITIONAL — only if needs_config is true) ---

// Configure applies startup configuration. Called once by the core.
func (p *{Name}Plugin) Configure(cfg map[string]any) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if cfg == nil {
		return nil
	}
	// Apply config keys with sensible defaults. Example:
	// if v, ok := cfg["schedule"].(string); ok {
	//  p.schedule = v
	// }
	return nil
}

// UpdateConfig validates and applies a single config key change.
func (p *{Name}Plugin) UpdateConfig(key string, value any) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	// Switch on key, validate, apply. Example:
	// switch key {
	// case "schedule":
	//  s, ok := value.(string)
	//  if !ok {
	//   return fmt.Errorf("schedule must be a string")
	//  }
	//  p.schedule = s
	// default:
	//  return fmt.Errorf("unknown config key: %s", key)
	// }
	return nil
}

// CurrentConfig returns the plugin's current configuration snapshot.
func (p *{Name}Plugin) CurrentConfig() map[string]any {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return map[string]any{
		// FILL: return all config keys. Example:
		// "schedule": p.schedule,
	}
}
```

> **Important:** If `needs_config` is false, omit the `var _ plugin.Configurable`
> check and the three `Configure`, `UpdateConfig`, `CurrentConfig` methods entirely.

### 3.3 — service.go

```go
package {pkg}

import (
	"log/slog"
	"sync"
)

// Service contains the business logic for the {name} plugin.
type Service struct {
	mu sync.Mutex

	// FILL: domain state fields here.
}

// FILL: Add methods matching the user's endpoints and job functions.
// Each method should:
//   - Lock the mutex if mutating state
//   - Use slog for structured logging: slog.Info("...", "plugin", "{name}")
//   - Return (result, error) tuples

// Example:
//
// func (s *Service) GetStatus() (*StatusResult, error) {
//  s.mu.Lock()
//  defer s.mu.Unlock()
//  slog.Info("fetching status", "plugin", "{name}")
//  return &StatusResult{}, nil
// }
```

### 3.4 — routes.go

```go
package {pkg}

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
)

type handler struct {
	svc *Service
}

func newRouter(svc *Service) http.Handler {
	r := chi.NewRouter()
	h := &handler{svc: svc}

	// FILL: register routes from the user's endpoints list. Examples:
	// r.Get("/status", h.handleStatus)
	// r.Post("/apply", h.handleApply)

	return r
}

// FILL: implement one handler function per route. Example:
//
// func (h *handler) handleStatus(w http.ResponseWriter, r *http.Request) {
//  result, err := h.svc.GetStatus()
//  if err != nil {
//   writeError(w, http.StatusInternalServerError, "status check failed", err.Error())
//   return
//  }
//  writeJSON(w, http.StatusOK, result)
// }

// --- Shared HTTP helpers ---

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode response", "plugin", "{name}", "error", err)
	}
}

func writeError(w http.ResponseWriter, status int, message, details string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	resp := map[string]any{
		"error": map[string]any{
			"code":    status,
			"message": message,
			"details": details,
		},
	}
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		slog.Error("failed to encode error response", "plugin", "{name}", "error", err)
	}
}
```

### 3.5 — plugin_test.go

```go
package {pkg}

import (
	"testing"

	"github.com/{OWNER}/config-manager-core/plugin"
)

func TestPluginInterface(t *testing.T) {
	p := New{Name}Plugin()

	if p.Name() == "" {
		t.Error("Name() must not be empty")
	}
	if p.Version() == "" {
		t.Error("Version() must not be empty")
	}
	if p.Description() == "" {
		t.Error("Description() must not be empty")
	}
}

func TestPluginName(t *testing.T) {
	p := New{Name}Plugin()
	if got := p.Name(); got != "{name}" {
		t.Errorf("Name() = %q, want %q", got, "{name}")
	}
}

func TestPluginVersion(t *testing.T) {
	p := New{Name}Plugin()
	if got := p.Version(); got == "" {
		t.Error("Version() must not be empty")
	}
}

func TestPluginRoutes(t *testing.T) {
	p := New{Name}Plugin()
	if p.Routes() == nil {
		t.Error("Routes() must not return nil")
	}
}

func TestPluginEndpoints(t *testing.T) {
	p := New{Name}Plugin()
	endpoints := p.Endpoints()
	if len(endpoints) == 0 {
		t.Error("Endpoints() must return at least one endpoint")
	}
	for _, ep := range endpoints {
		if ep.Method == "" {
			t.Error("Endpoint.Method must not be empty")
		}
		if ep.Path == "" {
			t.Error("Endpoint.Path must not be empty")
		}
	}
}

// CONDITIONAL: include only if Configurable is needed.
func TestPluginConfigurable(t *testing.T) {
	var p plugin.Configurable = New{Name}Plugin()
	if err := p.Configure(nil); err != nil {
		t.Fatalf("Configure(nil) error: %v", err)
	}

	cfg := p.CurrentConfig()
	if cfg == nil {
		t.Error("CurrentConfig() must not return nil")
	}
}
```

### 3.6 — service_test.go

```go
package {pkg}

import (
	"testing"
)

func TestServiceCreation(t *testing.T) {
	svc := &Service{}
	if svc == nil {
		t.Fatal("Service must not be nil")
	}
}

// FILL: add one test per Service method. Example:
//
// func TestServiceGetStatus(t *testing.T) {
//  svc := &Service{}
//  result, err := svc.GetStatus()
//  if err != nil {
//   t.Fatalf("GetStatus() error: %v", err)
//  }
//  if result == nil {
//   t.Fatal("GetStatus() returned nil")
//  }
// }
```

### 3.7 — routes_test.go

```go
package {pkg}

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	svc := &Service{}
	return httptest.NewServer(newRouter(svc))
}

// FILL: add one test per route. Example:
//
// func TestGetStatus(t *testing.T) {
//  ts := newTestServer(t)
//  defer ts.Close()
//
//  resp, err := http.Get(ts.URL + "/status")
//  if err != nil {
//   t.Fatalf("GET /status error: %v", err)
//  }
//  defer resp.Body.Close()
//
//  if resp.StatusCode != http.StatusOK {
//   t.Errorf("GET /status status = %d, want %d", resp.StatusCode, http.StatusOK)
//  }
//  if ct := resp.Header.Get("Content-Type"); ct != "application/json" {
//   t.Errorf("Content-Type = %q, want application/json", ct)
//  }
// }
//
// func TestPostApply(t *testing.T) {
//  ts := newTestServer(t)
//  defer ts.Close()
//
//  resp, err := http.Post(ts.URL+"/apply", "application/json", strings.NewReader(`{}`))
//  if err != nil {
//   t.Fatalf("POST /apply error: %v", err)
//  }
//  defer resp.Body.Close()
//
//  if resp.StatusCode != http.StatusOK {
//   t.Errorf("POST /apply status = %d, want %d", resp.StatusCode, http.StatusOK)
//  }
// }
```

> **Important:** Every test must use `httptest.NewServer` — never hardcoded ports.

### 3.8 — .github/workflows/ci.yml

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  markdownlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: DavidAnson/markdownlint-cli2-action@v22

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-go@v6
        with:
          go-version: "1.24"
      - name: Run golangci-lint
        uses: golangci/golangci-lint-action@v9
        with:
          version: v2.1.6

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-go@v6
        with:
          go-version: "1.24"
      - name: Run tests
        run: go test ./...
```

### 3.9 — .github/workflows/release.yml

```yaml
name: Release

on:
  push:
    tags:
      - "v*.*.*"

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-go@v6
        with:
          go-version: "1.24"

      - name: Verify build
        run: go build ./...

      - name: Verify tests
        run: go test ./...

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
```

> **Note:** Plugins are library packages compiled into the core binary — they
> do not produce standalone binaries or `.deb` packages. The release workflow
> only verifies the build and creates a GitHub release for the tag. The core
> repo's release workflow handles binary packaging with ldflags for all plugins.

### 3.10 — .golangci.yml

```yaml
version: "2"

linters:
  default: none
  enable:
    - errcheck
    - govet
    - ineffassign
    - staticcheck
    - unused
  settings:
    errcheck:
      check-blank: true
  exclusions:
    generated: lax
    presets:
      - comments
      - common-false-positives
      - legacy
      - std-error-handling
    rules:
      - linters:
          - errcheck
        path: _test\.go
    paths:
      - third_party$
      - builtin$
      - examples$

formatters:
  enable:
    - gofumpt
  exclusions:
    generated: lax
    paths:
      - third_party$
      - builtin$
      - examples$
```

### 3.11 — .markdownlint.json

```json
{
  "default": true,
  "MD003": { "style": "atx" },
  "MD004": { "style": "dash" },
  "MD007": { "indent": 2 },
  "MD009": { "br_spaces": 0 },
  "MD012": { "maximum": 1 },
  "MD013": false,
  "MD022": { "lines_above": 1, "lines_below": 1 },
  "MD024": false,
  "MD025": false,
  "MD026": false,
  "MD028": false,
  "MD029": { "style": "one_or_ordered" },
  "MD033": false,
  "MD034": false,
  "MD035": { "style": "---" },
  "MD036": false,
  "MD040": true,
  "MD041": false,
  "MD046": { "style": "fenced" },
  "MD048": { "style": "backtick" },
  "MD049": { "style": "asterisk" },
  "MD050": { "style": "asterisk" },
  "MD055": { "style": "leading_and_trailing" },
  "MD056": false,
  "MD059": false,
  "MD060": false
}
```

### 3.12 — .gitignore

```txt
# Go binaries
*.exe
*.test
*.out

# IDE files
.idea/
.vscode/
*.swp
*~

# Coverage
coverage.out
coverage.html

# Go workspace (local dev only)
go.work
go.work.sum
```

### 3.13 — dependabot.yml

Place this at `.github/dependabot.yml`.

```yaml
version: 2
updates:
  - package-ecosystem: gomod
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 3
```

### 3.14 — LICENSE (MIT)

```txt
MIT License

Copyright (c) {YEAR} {OWNER}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Replace `{YEAR}` with the current year at generation time.

### 3.15 — README.md

````markdown
# cm-plugin-{name}

{description} plugin for
[Config Manager](https://github.com/{OWNER}/config-manager-core). Designed for
headless Debian-based nodes (Raspbian Bookworm ARM64, Debian Bullseye slim).

## Features

<!-- FILL: one bullet per endpoint/capability. Example: -->
<!-- - Check current {name} status -->
<!-- - Apply {name} rules via REST API -->
<!-- - Scheduled periodic checks (if applicable) -->

## Documentation

- [Usage Guide](docs/USAGE.md) — endpoint examples and scheduled jobs
- [Specification](specs/SPEC.md) — responsibilities, integration, API routes
- [Architecture](specs/ARCHITECTURE.md) — internal structure

## Development

```bash
# lint
golangci-lint run

# test
go test ./...
```

CI runs automatically on push/PR to `main` via GitHub Actions
(`.github/workflows/ci.yml`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](LICENSE) for details.
````

### 3.16 — CONTRIBUTING.md

```markdown
# Contributing

Thank you for your interest in contributing to the Config Manager project!

## Getting Started

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Run tests: `go test ./...`
5. Run linter: `golangci-lint run`
6. Submit a pull request

## Guidelines

- Keep changes focused — one feature or fix per PR
- Write tests for new functionality
- Follow existing code style (enforced by `golangci-lint`)
- Update documentation if your change affects usage
- Commit messages should follow
  [Conventional Commits](https://www.conventionalcommits.org/)
  (e.g., `feat:`, `fix:`, `docs:`)

## Pull Request Process

1. Ensure CI passes (lint, test, markdownlint)
2. PRs are squash-merged into `main`
3. Maintainer will review and may request changes

## Project Structure

This project is split across multiple repositories. Read the full list from
the manifest at `$CM_REPO_BASE/.cm/project.json` → `repos[]`. At minimum:

- [config-manager-core](https://github.com/{OWNER}/config-manager-core) —
  core framework, plugin system, API server
- [cm-plugin-{name}](https://github.com/{OWNER}/cm-plugin-{name}) —
  {description}

All other plugins, TUI, and web repos are listed in the manifest.

## Code of Conduct

Be respectful and constructive. We are all here to learn and build together.
```

### 3.17 — .github/copilot-instructions.md

````markdown
# Copilot Instructions

## Project Overview

cm-plugin-{name} is a Go plugin for Config Manager that {description_lowercase}.
It provides endpoints to {endpoint_summary} and integrates with the core
scheduler and plugin registry.

Target platforms: Raspbian Bookworm (ARM64), Debian Bullseye slim.

## Architecture

- **plugin.go** — `{Name}Plugin` struct implementing `plugin.Plugin` from
  `config-manager-core`; registration handled by the core (no `init()`)
- **routes.go** — Chi router with handlers for {routes_list}; mounted by the
  core under `/api/v1/plugins/{name}`
- **service.go** — domain logic with mutex-protected state

## Integration

The plugin is compiled into the core binary via a normal import in
`cmd/cm/main.go`:

```go
import {pkg} "github.com/{OWNER}/cm-plugin-{name}"

plugin.Register({pkg}.New{Name}Plugin())
```

Routes are mounted under `/api/v1/plugins/{name}`.

## Conventions

- Main Go package is `package {pkg}` at the repo root
- Additional helper packages are allowed
- Use `github.com/go-chi/chi/v5` for HTTP routing
- Use `log/slog` for all structured logging (include `"plugin", "{name}"`)
- Error responses: `{"error": {"code": ..., "message": ..., "details": ...}}`
- Job IDs follow the pattern `{name}.{job_name}`
- Specs live in `specs/`, user docs in `docs/`
- Filenames use UPPERCASE-KEBAB-CASE (e.g., `SPEC.md`, `USAGE.md`)

## Specifications

- [specs/SPEC.md](../specs/SPEC.md) — plugin specification and scope
- [docs/USAGE.md](../docs/USAGE.md) — endpoint examples and scheduled jobs

## Validation

- All Go code must pass `golangci-lint run`
- All tests must pass: `go test ./...`
- CI runs markdownlint + lint + test via `.github/workflows/ci.yml`
- Never push directly to main — always use feature branches and PRs
````

### 3.18 — .github/PULL_REQUEST_TEMPLATE.md

```markdown
# Pull Request

## Description

What changed and why? Link any related issues.

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## Testing

Describe how this was tested.

- [ ] Unit tests added/updated
- [ ] Manual testing performed
- [ ] Tested on target architecture (ARM/Debian)

## Checklist

- [ ] All tests pass (`make test` or `go test ./...`)
- [ ] Linter is clean (`make lint` or `golangci-lint run`)
- [ ] Documentation updated (if applicable)
- [ ] No secrets or credentials committed
```

### 3.19 — .github/ISSUE_TEMPLATE/bug_report.md

```markdown
---
name: Bug Report
description: Report a bug or unexpected behavior
labels: ["bug"]
---

# Bug Report

## Describe the bug

A clear and concise description of what the bug is.

## To Reproduce

Steps to reproduce the behavior:

1. Run '...'
2. Configure '...'
3. See error

## Expected behavior

A clear and concise description of what you expected to happen.

## Environment

- **OS**: [e.g., Debian 12 Bookworm]
- **Architecture**: [e.g., arm64, amd64]
- **Version**: [e.g., v1.0.0]

## Additional context

Add any other context about the problem here, including logs or screenshots.
```

### 3.20 — .github/ISSUE_TEMPLATE/feature_request.md

```markdown
---
name: Feature Request
description: Suggest a new feature or improvement
labels: ["enhancement"]
---

# Feature Request

## Is your feature request related to a problem?

A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

## Describe the solution you'd like

A clear and concise description of what you want to happen.

## Describe alternatives you've considered

A clear and concise description of any alternative solutions or features you've considered.

## Additional context

Add any other context or screenshots about the feature request here.
```

### 3.21 — .github/ISSUE_TEMPLATE/config.yml

```yaml
blank_issues_enabled: true
contact_links:
  - name: Documentation
    url: https://github.com/{OWNER}/cm-plugin-{name}#readme
    about: Check the README for setup and usage instructions
```

### 3.22 — specs/SPEC.md

````markdown
# {Name} Plugin Specification

## 1. Purpose

{description}. This plugin provides a remotely-controllable interface for
managing {name} on headless Debian-based nodes.

## 2. Responsibilities

<!-- FILL: one bullet per responsibility. Example: -->
<!-- - **Check status** — query the current {name} state and report it. -->
<!-- - **Apply rules** — apply a new set of {name} rules atomically. -->

## 3. Non-responsibilities

<!-- FILL: explicitly state what this plugin does NOT do. -->

## 4. Integration

- Implements the core `plugin.Plugin` interface from `config-manager-core`.
- Does **not** call `plugin.Register()` in `init()`; registration is performed
  explicitly by the core integration layer when constructing the plugin.
- Included in the core binary via the normal dependency graph; the core wiring
  code instantiates and registers the plugin.
- Routes are mounted by the core API server under
  `/api/v1/plugins/{name}`.
- Scheduled jobs (if any) are registered with the core scheduler at startup.

## 5. API Routes

All routes are relative to the plugin mount point (`/api/v1/plugins/{name}`).

| Method | Path | Description |
| --- | --- | --- |
<!-- FILL: one row per endpoint from the user's initial endpoints list. -->

### Error Format

Errors follow the core convention:

```json
{
  "error": {
    "code": 400,
    "message": "error message",
    "details": "error details"
  }
}
```

## 6. Scheduled Jobs

<!-- CONDITIONAL: include only if needs_jobs is true. -->

| Job ID | Default Schedule | Description |
| --- | --- | --- |
<!-- FILL: one row per job. Example: -->
<!-- | {name}.check | `0 * * * *` | Periodic {name} check | -->

## 7. Configuration

<!-- CONDITIONAL: include only if needs_config is true. -->

The plugin exposes configuration via the `Configurable` interface.

```json
{
  // FILL: example config JSON
}
```

| Field | Type | Description |
| --- | --- | --- |
<!-- FILL: one row per config field. -->

## 8. Concurrency

- **Config access** is protected by a `sync.RWMutex`.
- Service methods that mutate state are guarded by a `sync.Mutex`.
````

### 3.23 — specs/ARCHITECTURE.md

````markdown
# {Name} Plugin Architecture

## Package Layout

```txt
cm-plugin-{name}/
├── plugin.go       — Plugin struct, interface methods, config
├── service.go      — Business logic, mutex-protected state
├── routes.go       — Chi router, HTTP handlers, JSON helpers
├── plugin_test.go  — Plugin interface contract tests
├── service_test.go — Service layer unit tests
└── routes_test.go  — HTTP handler tests (httptest.Server)
```

## Data Flow

```txt
HTTP Request
  → Chi Router (routes.go)
    → Handler function
      → Service method (service.go)
        → System interaction / state mutation
      ← Result / error
    ← JSON response
```

## Key Design Decisions

- **No `internal/` package** — all code lives in the root package unless a
  helper truly must not be exported.
- **httptest for all tests** — no hardcoded ports; each test gets its own
  `httptest.Server`.
- **`log/slog`** — structured logging with `"plugin", "{name}"` in every log
  call for easy filtering.
- **Chi router** — consistent with all other CM plugins.
- **Mutex strategy** — `sync.Mutex` in Service for state mutations,
  `sync.RWMutex` in Plugin for config access.
````

### 3.24 — docs/USAGE.md

````markdown
# Usage

## 1. Overview

The {name} plugin {description_lowercase}. All endpoints are available under
`/api/v1/plugins/{name}`.

## 2. Integration

The plugin is integrated into Config Manager by importing it and registering it
with the core's plugin registry:

```go
import {pkg} "github.com/{OWNER}/cm-plugin-{name}"

plugin.Register({pkg}.New{Name}Plugin())
```

> **Note:** The plugin implements the `plugin.Plugin` interface from
> `config-manager-core` directly.

## 3. API Endpoints

<!-- FILL: one subsection per endpoint with curl examples. Example: -->

<!-- ### Check status -->
<!--  -->
<!-- ```bash -->
<!-- curl http://localhost:7788/api/v1/plugins/{name}/status -->
<!-- ``` -->

## 4. Scheduled Jobs

<!-- CONDITIONAL: include only if needs_jobs is true. -->

| Job ID | Default Schedule | Description |
| --- | --- | --- |
<!-- FILL: one row per job. -->

## 5. Configuration

<!-- CONDITIONAL: include only if needs_config is true. -->

The plugin exposes configuration via `GET /config`:

```json
{
  // FILL: example config JSON
}
```

| Field | Type | Description |
| --- | --- | --- |
<!-- FILL: one row per config field. -->
````

## Step 4 — Run `go mod tidy` and Verify Build

```bash
cd cm-plugin-{name} || { echo "Failed to cd into cm-plugin-{name}"; exit 1; }
go mod tidy
go build ./...
go test ./...
golangci-lint run
```

All four commands must pass. Fix any issues before continuing.

## Step 5 — Wire Into Core

Edit `config-manager-core/cmd/cm/main.go` (sibling repo under the manifest's parent directory):

1. Add the import (alphabetical order among plugin imports):

   ```go
   {pkg} "github.com/{OWNER}/cm-plugin-{name}"
   ```

2. Add the registration call (in the same block as other `plugin.Register` calls):

   ```go
   plugin.Register({pkg}.New{Name}Plugin())
   ```

3. Run `go mod tidy` in `config-manager-core` to pull the new dependency:

   ```bash
   # Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
   _cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
   [ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
   [ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
   [ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
   if [ -f "$_cm" ]; then
     _base="$(cd "$(dirname "$_cm")/.." && pwd)"
     _ref="$(jq -r '.reference_repo' "$_cm")"
     cd "${_base}/${_ref}" || { echo "Error: failed to cd into ${_ref}" >&2; exit 1; }
   else
     echo "No manifest found — cd to the reference repo manually before continuing." >&2
     exit 1
   fi
   go get github.com/{OWNER}/cm-plugin-{name}@v0.1.0
   go mod tidy
   go build ./...
   go test ./...
   ```

> **Do not push changes to config-manager-core yet.** The core wiring will be
> part of a separate PR after the plugin's initial PR is merged and tagged.

## Step 5.5 — Update Core Build Flags

The core binary injects plugin versions at build time using ldflags. Add the
new plugin's version flag to both the Makefile and `release.yml` in
`config-manager-core`:

**Makefile** — add to the `LDFLAGS` variable:

```makefile
LDFLAGS += -X github.com/{OWNER}/cm-plugin-{name}.version=$(CLEAN_VERSION)
```

**`.github/workflows/release.yml`** — add to the `-ldflags` string in the
build step:

```txt
-X github.com/{OWNER}/cm-plugin-{name}.version=${VERSION}
```

Without this step, the new plugin will always report `"dev"` in production
builds even though the `var version` variable exists.

## Step 5.6 — Register in go.work

Add the new plugin to the workspace file for local cross-repo development:

```bash
cd "$_base" && go work use "cm-plugin-{name}"
```

Verify:

```bash
go work sync
```

## Step 6 — Add to GitHub Project Board

Link the new repository to the project board (note: `item-add` only accepts
issues/PRs, so use `project link` for repositories):

```bash
gh project link {PROJECT_NUMBER} --owner {OWNER} --repo {OWNER}/cm-plugin-{name}
```

## Step 7 — Commit and Create Initial PR

```bash
cd cm-plugin-{name} || { echo "Failed to cd into cm-plugin-{name}"; exit 1; }
git add -A
git commit -m "feat: scaffold {name} plugin skeleton

Initial plugin skeleton with:
- plugin.Plugin interface implementation
- Chi router with endpoint handlers
- Service layer with mutex-protected state
- Unit tests (plugin, service, routes with httptest)
- CI workflow (golangci-lint v2 + go test + markdownlint)
- Release workflow (GitHub release on tag)
- Specs, docs, and repository boilerplate

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push -u origin phase1/skeleton-and-specs
```

Create the PR:

```bash
gh pr create \
  --repo {OWNER}/cm-plugin-{name} \
  --base main \
  --head phase1/skeleton-and-specs \
  --title "feat: scaffold {name} plugin skeleton and specs" \
  --body "## Summary

Initial plugin scaffold for **cm-plugin-{name}** — {description}.

### What's included

- \`plugin.go\` — \`{Name}Plugin\` implementing \`plugin.Plugin\` and \`plugin.Configurable\` (if needs_config)
- \`service.go\` — business logic layer
- \`routes.go\` — Chi router with endpoint handlers
- Unit tests (\`plugin_test.go\`, \`service_test.go\`, \`routes_test.go\`)
- CI workflow (golangci-lint v2 + go test + markdownlint)
- Release workflow (GitHub release on \`v*.*.*\` tag)
- \`specs/SPEC.md\` and \`specs/ARCHITECTURE.md\`
- \`docs/USAGE.md\`
- Repository boilerplate (.gitignore, dependabot, issue templates, etc.)

### Next steps

1. Merge this skeleton
2. Wire into \`config-manager-core/cmd/cm/main.go\`
3. Implement domain logic in \`service.go\`"
```

## Step 8 — Verification Checklist

Before reporting completion, verify all of the following:

- [ ] GitHub repo `{OWNER}/cm-plugin-{name}` exists and is public
- [ ] All files from the tree in Step 2 are present
- [ ] `go build ./...` succeeds
- [ ] `go test ./...` passes
- [ ] `golangci-lint run` is clean
- [ ] CI workflow file matches the exact pattern (checkout@v6, setup-go@v6, golangci-lint-action@v9 v2.1.6, markdownlint-cli2-action@v22)
- [ ] Release workflow uses `softprops/action-gh-release@v2` (no binary build, no nfpm)
- [ ] PR exists on branch `phase1/skeleton-and-specs`
- [ ] Repo is on the project board
- [ ] Core wiring import + Register() call added to `main.go` (local only, not pushed)
- [ ] Core Makefile + release.yml ldflags updated with `-X` flag for new plugin (Step 5.5)
- [ ] Plugin registered in `go.work` (Step 5.6)
- [ ] `Version()` uses `var version = "dev"` pattern (not hardcoded string)
- [ ] Branch protection configured on `main` (Step 10)

## Step 9 — Update Project Manifest

After the plugin repo is created, update the project manifest so scripts discover it:

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  # Only add if not already present
  if ! jq -e '.repos[] | select(.name == "cm-plugin-{name}")' "$_cm" >/dev/null 2>&1; then
    jq '.repos += [{"name": "cm-plugin-{name}", "role": "{role}"}]
        | if .dep_order then
            # Insert after plugins but before UI repos (tui/web).
            # Find the index of the first UI repo and splice there.
            (.dep_order | to_entries
              | map(select(.value | test("tui|web"))) | .[0].key // length) as $idx
            | .dep_order = (.dep_order[:$idx] + ["cm-plugin-{name}"] + .dep_order[$idx:])
          else . end' "$_cm" \
      > "$(dirname "$_cm")/project.tmp.$$.json" \
      && mv "$(dirname "$_cm")/project.tmp.$$.json" "$_cm"
  fi
else
  echo "No manifest found — create one with init-project.sh to register the new plugin." >&2
fi
```

Verify the manifest is valid (if it exists):

```bash
if [ -f "$_cm" ]; then
  jq '.' "$_cm"
fi
```

## Step 10 — Configure Branch Protection

Set up branch protection on `main` to enforce PR workflow:

```bash
gh api -X PUT "repos/{OWNER}/cm-plugin-{name}/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint", "test", "markdownlint"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

> If the repo is new and has no CI runs yet, GitHub may reject status check
> names. In that case, push a dummy commit, wait for CI to run, then re-apply.

## Rules

- Use `internal/` for non-exported packages **only if needed**; prefer the root package.
- Plugin routes mount under `/api/v1/plugins/{name}`.
- Job IDs follow `{plugin_name}.{job_name}` pattern (e.g., `firewall.apply`).
- Use `log/slog` for logging — include `"plugin", "{name}"` in every call.
- Use `gopkg.in/yaml.v3` for YAML parsing if needed.
- Use `github.com/go-chi/chi/v5` for HTTP routing.
- Error responses use `{"error": {"code": ..., "message": ..., "details": ...}}`.
- Every test file uses `httptest.Server` — never hardcoded ports.
- `.markdownlint.json` must match the version in Step 3.11 exactly.
- `dependabot.yml` watches `gomod` + `github-actions` on a weekly schedule.
- License is MIT.
- Never push directly to `main` — always use feature branches and PRs.
