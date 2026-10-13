---
name: configarr-configuration
description: 'Configure Configarr config.yml for Sonarr, Radarr, and other *Arr instances, including TRaSH-Guides and Recyclarr template includes, quality profiles, custom formats, secrets, and dry-run validation.'
argument-hint: 'Describe the Configarr instance and desired configuration or quality-profile behavior'
---

# Configarr Configuration

Use this skill for Configarr's application configuration (`config.yml`), including quality profiles, custom-format assignments, and template includes. For bjw-s app-template chart mechanics, also follow [bjw-s-app-template](../bjw-s-app-template/SKILL.md).

## Procedure

1. **Inspect the current deployment and version.** Read `apps/media/configarr/Chart.yaml` and `apps/media/configarr/values.yaml`. Check the image tag, how `/app/config/config.yml` is provided, which environment variables are injected, and whether `/app/repos` is persistent. Do not confuse Configarr's `config.yml` with Helm values. The current chart pins Configarr `1.33.0` and persists `/app/repos`, but does not mount the required Configarr config file or inject API keys. Treat the files in the workspace as the source of truth if they change.
2. **Check the upstream documentation against the pinned image.** Documentation on `main` can describe features added after the deployed version. Check each relevant feature's version note and the release history before using it. For example, the current docs mark managed `tags` as requiring `1.34.0`, so do not configure that feature with the current `1.33.0` image. Configarr `1.33.0` supports the post-February-2026 TRaSH-Guides format; enable `compatibilityTrashGuide20260219Enabled` only when intentionally using the older behavior, after checking the [FAQ](https://github.com/raydak-labs/configarr/blob/main/docs/docs/faq.md#trash-guides-breaking-changes-2026-02).
3. **Locate the configuration and protect credentials.** Configarr's default config path is `/app/config/config.yml` (`CONFIG_LOCATION` can override it). Use the existing repo's ConfigMap, Secret, or ExternalSecret patterns when deployment changes are requested. Prefer `!env` values backed by Kubernetes Secrets; never put API keys in committed files or plaintext Helm values. `!secret` with a mounted `secrets.yml` and `!file` are alternatives documented upstream. Do not assume the current chart can consume a config file until its mount is added.
4. **Make only the requested configuration change.** Follow the documented top-level and per-instance structure. Check the actual *Arr application version and API endpoint, use the correct `sonarr` or `radarr` block and instance name, and preserve existing settings. For profile/template work, use the upstream [Quality Profiles: existing base templates](https://github.com/raydak-labs/configarr/blob/main/docs/docs/profiles/index.mdx#existing-base-templates) page to find TRaSH-Guides and Recyclarr templates. Do not copy a profile catalog into this skill or invent template names, TRaSH IDs, quality names, or profile names. Match `custom_formats.assign_scores_to` names to the profile created or loaded by the includes. Keep optional local custom formats and templates under their configured paths and add mounts only when the requested change needs them.
5. **Preserve safe sync behavior.** Configarr merges TRaSH data, Recyclarr templates, local files, then global and instance config, with later configuration taking precedence. Leave `delete_unmanaged_*` options disabled unless explicitly requested and the config is intended to be the full source of truth. Before a live sync, run with `DRY_RUN=true` in the intended environment and review the diff/logs for every instance, especially profile, score, and deletion changes. Do not trigger a live cluster run or deploy unless asked.
6. **Validate the right layer.** Validate Configarr YAML with Configarr or a YAML parser that supports its `!env`, `!secret`, and `!file` tags; a generic parser rejecting those tags is not sufficient. Check every referenced environment variable is injected, every include resolves for the configured source, and profile names match. If Helm values or mounts changed, also follow the app-template skill's dependency, lint, and render checks.

## Documentation Routes

Use the configuration reference for detailed keys and examples; expand to related pages only for the behavior being changed.

- Overview and supported applications: [Introduction](https://github.com/raydak-labs/configarr/blob/main/docs/docs/intro.mdx) and [Concepts](https://github.com/raydak-labs/configarr/blob/main/docs/docs/concepts.md)
- File structure, templates, profiles, custom formats, and configuration options: [Configuration file](https://github.com/raydak-labs/configarr/blob/main/docs/docs/configuration/config-file.md)
- Environment variables and custom YAML behavior: [Environment variables](https://github.com/raydak-labs/configarr/blob/main/docs/docs/configuration/environment-variables.md)
- Merge precedence, paths, dry runs, and diff reports: [Basics](https://github.com/raydak-labs/configarr/blob/main/docs/docs/configuration/general.md)
- Quality-profile templates (do not reproduce the profile list here): [Existing base templates](https://github.com/raydak-labs/configarr/blob/main/docs/docs/profiles/index.mdx#existing-base-templates)
- Worked configuration patterns: [HowTos and examples](https://github.com/raydak-labs/configarr/blob/main/docs/docs/examples.md)
- Kubernetes mounts and app-template example: [Kubernetes installation](https://github.com/raydak-labs/configarr/blob/main/docs/docs/installation/kubernetes.md)
- Scheduled runs: [Scheduling](https://github.com/raydak-labs/configarr/blob/main/docs/docs/configuration/scheduled.md)
- Feature limitations for other *Arr apps: [Experimental support](https://github.com/raydak-labs/configarr/blob/main/docs/docs/configuration/experimental-support.md)
- Troubleshooting and TRaSH format changes: [FAQ](https://github.com/raydak-labs/configarr/blob/main/docs/docs/faq.md)
