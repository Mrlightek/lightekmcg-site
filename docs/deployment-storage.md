# Deployment storage recovery

A full filesystem can interrupt a release after dependency images finish building but before migrations and service restarts. In the November 11 Studio release, Blender passed its readiness check, then writing `tmp/live-audience-image.new` failed with `No space left on device`.

## Immediate recovery on the server

As root on `mail.lightekmcg.com`:

```bash
docker builder prune --all --force
df -h / /var/lib/docker /var/lib/containerd
df -i / /var/lib/docker /var/lib/containerd
docker system df
```

The prune targets unused build cache. It retains application data, tagged dependency images, containers and volumes. The next cold build may take longer. Do not remove files under Docker/containerd by hand, and do not prune volumes to recover a deployment.

If space remains low, review disk allocation and image/storage usage before retrying. This deployment fix does not delete older dependency image versions, backups, media, mail or database data automatically. A larger disk is still necessary if the retained working set plus deployment headroom exceeds capacity.

After recovery, deploy the latest release through the normal pipeline. Rerunning an old job is rejected if the server checkout has already advanced beyond that release. Successful completion must include migrations, service restarts and the `/up` health check; a built image alone does not establish a successful release.

## Automatic protection

`lib/scripts/deployment_storage.py` checks available bytes and inodes on the application's filesystem, the Docker data filesystem and `/var/lib/containerd` when present. Shared filesystems are checked once. Under pressure it tries to reclaim unused build cache, then measures again. If there is still insufficient room it fails with an explicit capacity error while retaining persistent data and images.

Deployment requires at least 2048 MiB and 4096 free inodes before bundle installation and again before migrations. Cold Studio media and desktop builds require 4096 MiB before starting and retain a 2048 MiB reserve afterwards. Live audience builds use the same helper with a 2048 MiB initial requirement. These are minimum gates, not guarantees that every future image build fits.

Dependency builds label their source fingerprint. An unchanged label skips the build. An existing unlabelled version-tagged image may be adopted when its creation time is later than the latest clean tracked dependency-context commit; dirty sources and older images trigger a build. The media engine's restricted Blender probe still runs on reuse. Explicit registry image overrides retain their existing inspect/pull behavior.

The preflight runs after release checkout. A host that is already completely full may need the immediate recovery commands before Git can write the checkout or fetch the fix.

## Validation

The storage tests cover cache-only reclamation, repeated checks, byte/inode exhaustion, refusing unsafe cold builds, source fingerprint reuse, changed-source rebuilds and legacy adoption. The shell integration test proves a reused media image still runs its restricted Blender probe. Release checkout/bootstrap regressions remain covered. Actual production free space and a successful rerun must be checked on the server.
