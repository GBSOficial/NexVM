# ADR-0004 — `.nexvm` bundle format v1

Status: accepted

```
<uuid>.nexvm/
  manifest.json   {formatVersion, vmID, createdAt}
  config.json     VMConfiguration (schemaVersion 1)
  disks/          raw sparse images (qcow2 supported by the model; creation needs qemu-img, not implemented)
  logs/  metadata/
  .lock           flock(2) advisory lock held while a VM runs
```
- Directory name is the VM UUID, so user-controlled names never become paths.
- Create: build in `.staging-*`, then atomic rename. Save: atomic file replace. A crash leaves the previous config.
- Schema: `ConfigurationMigrator` rejects unknown future versions (`unsupportedSchema`) instead of guessing; add upgrade steps there.
- "Remove from library" moves to `<library>/.removed/` (data kept). "Delete data" requires `DeletionConfirmation(confirmingDeletionOf: id)`, a matching id, and an unlocked bundle.
- Install ISOs are referenced by absolute path, never copied or modified.
- Dates are stored as ISO-8601 whole seconds.
