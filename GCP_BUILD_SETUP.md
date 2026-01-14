# GCP Cloud Build Setup for Godot Joy-Con Fix

## Overview

This project uses Google Cloud Build instead of GitHub Actions runners to avoid "no space left on device" errors. GCP provides 100GB disk space and efficient caching.

## Architecture

```
GitHub Push → GitHub Actions → GCP Cloud Build → Build Godot → Push to Artifact Registry
                                                 ↓
                                            Store APKs in GCS
```

## Resources

- **Project ID:** `general-476320`
- **Region:** `europe-west1`
- **Artifact Registry:** `europe-west1-docker.pkg.dev/general-476320/android-build-images`
- **Service Account:** `nys-godot-game-builder@general-476320.iam.gserviceaccount.com`
- **GCS Bucket:** `gs://general-476320_cloudbuild/godot-joycon-fix/`

## GitHub Secrets Required

Set these in GitHub repo Settings → Secrets and variables → Actions:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `GCP_SA_KEY` | `{...json content...}` | Service account JSON key |
| `GCP_PROJECT_ID` | `general-476320` | GCP project ID |
| `GCP_REGION` | `europe-west1` | GCP region |
| `GCP_ARTIFACT_REGISTRY` | `europe-west1-docker.pkg.dev/general-476320/android-build-images` | Artifact Registry path |

## How It Works

### Automatic Builds

Push to these branches triggers Cloud Build automatically:
- `4.3-joycon-fix`
- `main`

Watching these file changes:
- `**/*.cpp`, `**/*.h`, `**/*.java`
- `platform/android/**`
- `Dockerfile`, `cloudbuild.yaml`

### Manual Builds

Trigger via GitHub Actions UI:
1. Go to Actions tab
2. Select "Build with Google Cloud Build"
3. Click "Run workflow"
4. Optionally specify Godot version

## Build Outputs

### Docker Images (Artifact Registry)

```bash
# Pull latest build
docker pull europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix:4.3-joycon-fix

# Pull specific commit
docker pull europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix:abc1234
```

### APK Files (Google Cloud Storage)

```bash
# Download debug APK
gsutil cp gs://general-476320_cloudbuild/godot-joycon-fix/4.3-joycon-fix/<SHORT_SHA>/android_debug.apk ./

# Download release APK
gsutil cp gs://general-476320_cloudbuild/godot-joycon-fix/4.3-joycon-fix/<SHORT_SHA>/android_release.apk ./
```

Also available as GitHub Actions artifacts (30 day retention).

## Cloud Build Configuration

See `cloudbuild.yaml` for build steps:
1. Build Docker image with Godot
2. Push to Artifact Registry
3. Extract APKs from image
4. Upload APKs to GCS
5. Store as build artifacts

## Build Resources

- **Machine Type:** E2_STANDARD_2 (2 vCPUs, free tier eligible)
- **Disk Size:** 100GB
- **Timeout:** 4 hours (extended for limited CPU resources)
- **Cost:** Free tier (120 build-minutes/day free for E2_STANDARD_2)

> **Note:** Builds on E2_STANDARD_2 take longer than on higher-tier machines due to limited CPU. Expect 2-3+ hours for a full build with Android export templates. The 4-hour timeout provides headroom for first-time builds without cache.

## Monitoring

### View Build Logs

```bash
# List recent builds
gcloud builds list --region=europe-west1 --limit=10

# View specific build
gcloud builds log <BUILD_ID> --region=europe-west1

# Stream live logs
gcloud builds log <BUILD_ID> --region=europe-west1 --stream
```

### Cloud Console Links

- [Cloud Build History](https://console.cloud.google.com/cloud-build/builds?region=europe-west1&project=general-476320)
- [Artifact Registry](https://console.cloud.google.com/artifacts/docker/general-476320/europe-west1/android-build-images?project=general-476320)
- [GCS Bucket](https://console.cloud.google.com/storage/browser/general-476320_cloudbuild?project=general-476320)

## Troubleshooting

### Build Fails with Auth Error

Check service account permissions:
```bash
gcloud projects get-iam-policy general-476320 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com"
```

### Out of Disk Space (even with 100GB)

Increase disk size in `cloudbuild.yaml`:
```yaml
options:
  diskSizeGb: 200
```

### Build Timeout

If builds exceed 4 hours, increase timeout in `cloudbuild.yaml`:
```yaml
timeout: 21600s  # 6 hours
```

> **Note:** With E2_STANDARD_2 (2 vCPUs), full Godot builds with Android templates can take 2-4 hours depending on cache state.

## Local Testing

Test Cloud Build locally before pushing:

```bash
# Install Cloud Build Local Builder
gcloud components install cloud-build-local

# Run build locally
cloud-build-local --config=cloudbuild.yaml --dryrun=false .
```

## Cost Optimization

- Builds use cached layers from previous builds
- APKs older than 30 days auto-delete from GCS (lifecycle policy)
- Docker images: manual cleanup recommended

```bash
# Delete old images
gcloud artifacts docker images delete \
  europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix:<OLD_TAG> \
  --delete-tags
```
