# Install and use Ubuntu applications

Host application control requires the super administrator on a native Ubuntu deployment. A package is installed software; an adapter defines the operations Nevaeh can call.

## Discover and inspect

```text
/ubuntu status
/ubuntu refresh
/ubuntu search video
/ubuntu show ffmpeg
/ubuntu plan ffmpeg
```

Refresh updates configured package indexes, not installed applications. Search uses those indexes. Show reports installed/candidate versions and origin metadata. Plan reports dependency changes, download size and disk changes without installing.

## Connect a supported application in one step

```text
/ubuntu setup ffmpeg
/app describe ffmpeg
/app run ffmpeg version
```

Setup installs the selected package candidate, imports its installed documentation into KB, activates the supplied typed recipe and verifies the actual application version. It preserves existing active adapters. To obtain newly published candidates, refresh indexes before setup; a package watcher does this when refreshing is enabled.

FFmpeg has version, probe and transcode recipes; Pandoc has version and conversion. Blender's package recipe verifies its version, while Studio provides its authoring operations. Other packages become documented drafts until reviewed operation contracts are authored.

## Process a file

Upload an input using Application Fabric. Copy its returned filename:

```text
/app run ffmpeg probe {"input":"UPLOAD_FILENAME.wav"}
/app run ffmpeg transcode {"input":"UPLOAD_FILENAME.wav","output":"converted.mp4"}
```

Replace UPLOAD_FILENAME with the exact returned name. Inputs and outputs stay in your application workspace; output names cannot overwrite an existing file. Download successful outputs from the receipt.

## Extend an application adapter

Use `/ubuntu integrate PACKAGE`, read its application_adapters record, review its executable inventory/documentation, and edit typed operations through the CRUD contract. An operation contains fixed argv plus file/output/integer/enum inputs. Edits invalidate activation. `/app activate PACKAGE` validates the reviewed contract.

The application runner is unprivileged and does not use a shell, but it is not an OS/container sandbox. Package installation can start services and cannot be undone by rolling back a database action.

If the helper is missing, use the normal deployment/update pipeline. Docker-hosted Rails requires a deliberate host transport; installing into an ephemeral application container is not host installation.
