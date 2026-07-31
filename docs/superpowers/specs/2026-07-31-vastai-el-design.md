# vastai.el Design Spec

**Date:** 2026-07-31  
**Status:** Approved

## Overview

A single-file Emacs package (`vastai.el`) that wraps the Vast.ai REST API for managing GPU instances, searching offers, browsing templates, and viewing costs — all driven by a transient menu with `completing-read` for selection.

---

## Architecture

- **Single file:** `vastai.el` with `lexical-binding: t`
- **Emacs requirement:** 28.1+
- **Dependencies:** `transient` and `json` (both built-in to Emacs 28+); no external packages
- **HTTP:** `url-retrieve-synchronously` — synchronous, blocking, no extra deps
- **Base URL:** `https://console.vast.ai`

### Core HTTP layer

One function handles all requests:

```elisp
(defun vastai--request (method endpoint &optional params body))
```

- Builds URL from base + endpoint + optional query params alist
- Sets `Authorization: Bearer <key>` and `Content-Type: application/json` headers
- Parses response JSON via `json-read`
- Returns parsed alist on success, `nil` on error (and calls `message` with the error)

### Auth resolution

```elisp
(defun vastai--api-key ())
```

Resolution order:
1. `vastai-api-key` custom variable (if non-nil)
2. Contents of `vastai-api-key-file` (default `~/.config/vastai/vast_api_key`)
3. Signals `user-error` with setup instructions if neither found

### Customization group

```elisp
(defgroup vastai nil "Vast.ai API interface." :prefix "vastai-" :group 'tools)
(defcustom vastai-api-key nil ...)
(defcustom vastai-api-key-file "~/.config/vastai/vast_api_key" ...)
```

---

## API Endpoints

Base: `https://console.vast.ai`

| Feature | Method | Endpoint | Notes |
|---|---|---|---|
| List instances | GET | `/api/v1/instances/` | v1, not v0 |
| Stop instance | PUT | `/api/v0/instances/{id}/` | body: `{"state":"stopped"}` |
| Start instance | PUT | `/api/v0/instances/{id}/` | body: `{"state":"running"}` |
| Delete instance | DELETE | `/api/v0/instances/{id}/` | |
| Search offers | POST | `/api/v0/bundles/` | JSON body with filter alist |
| List templates | GET | `/api/v0/template/` | singular, not plural |
| Show costs | GET | `/api/v0/charges/` | |

**Auth:** `Authorization: Bearer <api-key>` header on every request.

---

## UI Design

### Top-level transient (`M-x vastai`)

```
vastai
────────────────────────────────
 Instances
 [l] List & act on instances

 Search
 [s] Search offers

 Templates
 [t] List & select template

 Costs
 [c] Show recent charges
```

### Instances flow

1. `[l]` fetches `/api/v1/instances/`
2. Candidates formatted as: `"<id> | <status> | <num_gpus>x <gpu_name> | $<dph_total>/hr | <label>"`
3. `completing-read` → user selects instance
4. Instance action transient appears:

```
vastai instance <id>
────────────────────────────────
 [s] Stop     [S] Start
 [d] Delete   [i] Show details
```

5. Stop and Delete gate on `y-or-n-p` before firing
6. Show details renders JSON fields to `*vastai*` buffer

### Search offers flow

1. `[s]` prompts: `"Filter (e.g. gpu_name=RTX_4090 num_gpus=1): "`
2. Parses filter string into JSON body alist
3. POSTs to `/api/v0/bundles/`
4. Candidates formatted as: `"<id> | <gpu_name> <num_gpus>x | $<dph_total>/hr | <geolocation>"`
5. `completing-read` → selected offer details shown in `*vastai*` buffer

### Templates flow

1. `[t]` fetches `/api/v0/template/`
2. Candidates formatted as: `"<name> | <image> | <hash_id>"`
3. `completing-read` → selected template details shown in `*vastai*` buffer

### Costs flow

1. `[c]` prompts for date range (defaults: last 7 days)
2. GETs `/api/v0/charges/` with date filters
3. Results rendered to `*vastai*` read-only buffer

---

## Output Buffer

- Name: `*vastai*`
- Mode: `special-mode` (read-only, `q` to quit)
- Used for: instance details, offer details, template details, cost results
- Content: formatted key/value pairs from the API response alist

---

## Error Handling

- HTTP non-2xx or JSON parse failure: `vastai--request` returns `nil`, calls `(message "vastai: <error>")`
- Missing API key: `(user-error "vastai: set vastai-api-key or run: vastai set api-key <KEY>")`
- Empty results from API: `(message "vastai: no results")`, no completing-read shown
- Destructive actions (stop, delete): always gated by `(y-or-n-p "...")`

---

## File Structure

```
vastai.el/
├── vastai.el                          ← the package (single file)
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-07-31-vastai-el-design.md
```

---

## Verification Plan

1. `M-x load-file` → `vastai.el` — no errors on load
2. `M-x vastai` — transient appears with all four keys
3. `[l]` — running instances appear in `completing-read`
4. `[s]` — offer search with a simple filter populates results
5. `[t]` — templates populate
6. `[c]` — charges appear in `*vastai*` buffer
7. Stop/delete tested only against a throwaway instance (not current running ones)
