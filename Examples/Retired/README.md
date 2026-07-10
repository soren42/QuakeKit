# Consolidated Example Packages

These pre-RC1 examples are retained as migration references and are intentionally
outside `Examples/Plugins`, so the host does not load duplicate launcher entries.

- `spotify-controls` and `spotify-current-track` are consolidated into `music-now-playing` (`Music`).
- Individual LLM harnesses plus `ai-agent-companions` and `ai-workbench` are consolidated into `ai-agent` (`AI Command Center`).

The RC1 packages preserve the offline-safe adapters, explicit settings, and action
contracts while presenting one source-selectable interface for each domain.
