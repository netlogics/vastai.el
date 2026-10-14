# vastai.el

Emacs interface for the [Vast.ai](https://vast.ai) GPU cloud API. Manage GPU instances, search offers, browse templates, and view costs — all from Emacs.

## Requirements

- Emacs 28.1+
- `transient` (included with Emacs)
- Vast.ai API key

## Installation

Add to your Emacs configuration:

```elisp
(use-package vastai
  :ensure t
  :config
  (setq vastai-api-key "your-api-key-here")
  ;; or use a file:
  ;; (setq vastai-api-key-file "~/.config/vastai/vast_api_key"))
```

Alternatively, place your API key at the default location: `~/.config/vastai/vast_api_key`.

## Usage

Run `M-x vastai` to open the main transient menu.

### Commands

| Command | Description |
|---------|-------------|
| `vastai` | Open the main menu (all commands) |
| `vastai-list-instances` | List your running instances, then manage them |
| `vastai-search-offers` | Search available GPU offers by filter |
| `vastai-toggle-offer-type` | Toggle between on-demand and interruptible offers |
| `vastai-list-templates` | Browse available VM templates |
| `vastai-show-costs` | View recent charges and spending |

### Instance Management

After selecting an instance from the list, use the action transient:

| Key | Action |
|-----|--------|
| `s` | Stop instance |
| `S` | Start instance |
| `d` | Delete instance |
| `i` | Show instance details |

### Offer Search

The search command supports filter strings like:

```
gpu_name=RTX_4090 num_gpus=1
```

Values with underscores are converted to spaces. Wrap in quotes to preserve underscores:

```
image_uuid="abc123_v1"
```

#### Offer type

Only **on-demand** offers are searched by default. To search
**interruptible** (spot) offers — cheaper, but preemptible — toggle with
`M-x vastai-toggle-offer-type` (or `T` in the main menu and the
`*vastai*` buffer); the current type is shown in the search prompt. No
filter token is required.

Set `vastai-offer-type` directly to pin a type: `"on-demand"`, `"bid"`
(interruptible), or `"reserved"`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `vastai-api-key` | `nil` | Vast.ai API key (string) |
| `vastai-api-key-file` | `~/.config/vastai/vast_api_key` | Path to file containing the API key |
| `vastai-offer-type` | `"on-demand"` | Offer type `vastai-search-offers` queries: `"on-demand"`, `"bid"` (interruptible), or `"reserved"` |

## License

See the source file for license information.