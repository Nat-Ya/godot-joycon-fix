# GitHub Workflow with Cloud Build - Next Steps Checklist

## ✅ Completed
- [x] Created `cloudbuild.yaml` configuration
- [x] Created `.github/workflows/gcp-cloudbuild.yml` workflow
- [x] Created service account: `nys-godot-game-builder@general-476320.iam.gserviceaccount.com`
- [x] Created Artifact Registry repository: `europe-west1-docker.pkg.dev/general-476320/android-build-images`
- [x] Generated service account JSON key

---

## 📋 TODO: GitHub Repository Setup

### Step 1: Add GitHub Secrets

Go to: `https://github.com/Nat-Ya/godot-joycon-fix/settings/secrets/actions`

Click "New repository secret" and add these **4 secrets**:

| Secret Name | Value | How to Get |
|-------------|-------|------------|
| `GCP_SA_KEY` | `{...entire JSON key content...}` | Copy entire JSON file content |
| `GCP_PROJECT_ID` | `general-476320` | Your GCP project ID |
| `GCP_REGION` | `europe-west1` | Your chosen region |
| `GCP_ARTIFACT_REGISTRY` | `europe-west1-docker.pkg.dev/general-476320/android-build-images` | Your Artifact Registry path |

**How to add secrets:**
```bash
# Copy JSON key to clipboard (if on Linux with xclip)
cat /path/to/nys-godot-game-builder-key.json | xclip -selection clipboard

# Or view and copy manually
cat /path/to/nys-godot-game-builder-key.json
```

Then:
1. Go to repo Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `GCP_SA_KEY`
4. Value: Paste entire JSON content
5. Click "Add secret"
6. Repeat for other 3 secrets

---

## 📋 TODO: GCP Service Account Permissions

### Step 2: Grant Required IAM Roles

Run these commands in Google Cloud Shell or locally with `gcloud`:

```bash
# Authenticate (if not already)
gcloud auth login
gcloud config set project general-476320

# Grant Cloud Build permissions
gcloud projects add-iam-policy-binding general-476320 \
  --member="serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

# Grant Artifact Registry write permissions
gcloud projects add-iam-policy-binding general-476320 \
  --member="serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Grant Cloud Storage permissions (for APK artifacts)
gcloud projects add-iam-policy-binding general-476320 \
  --member="serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Grant logging permissions (optional but recommended)
gcloud projects add-iam-policy-binding general-476320 \
  --member="serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"
```

**Verify permissions:**
```bash
gcloud projects get-iam-policy general-476320 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:nys-godot-game-builder@general-476320.iam.gserviceaccount.com"
```

You should see all 4 roles listed.

---

## 📋 TODO: Enable GCP APIs

### Step 3: Enable Required APIs

```bash
# Enable Cloud Build API
gcloud services enable cloudbuild.googleapis.com --project=general-476320

# Enable Artifact Registry API
gcloud services enable artifactregistry.googleapis.com --project=general-476320

# Enable Cloud Storage API
gcloud services enable storage.googleapis.com --project=general-476320

# Enable Container Registry API (for Docker)
gcloud services enable containerregistry.googleapis.com --project=general-476320

# Verify enabled APIs
gcloud services list --enabled --project=general-476320 | grep -E "cloudbuild|artifact|storage|container"
```

---

## 📋 TODO: Create GCS Bucket for Artifacts

### Step 4: Create Storage Bucket (if not exists)

```bash
# Create bucket for build artifacts (APKs)
gsutil mb -p general-476320 -l europe-west1 gs://general-476320_cloudbuild/

# Set lifecycle policy to delete old artifacts (optional - save costs)
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["godot-joycon-fix/"]
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set lifecycle.json gs://general-476320_cloudbuild/
rm lifecycle.json

# Verify bucket
gsutil ls -L gs://general-476320_cloudbuild/
```

---

## 📋 TODO: Test the Setup

### Step 5: Trigger First Build

**Option A: Push to trigger automatic build**

```bash
# Make sure you're on 4.3-joycon-fix branch
git checkout 4.3-joycon-fix

# Merge your changes
git merge claude/fix-godot-screenshot-button-1ysda

# Push to trigger build
git push origin 4.3-joycon-fix
```

**Option B: Manual workflow trigger**

```bash
# Install GitHub CLI if not installed
sudo apt install gh

# Authenticate
gh auth login

# Trigger build manually
gh workflow run gcp-cloudbuild.yml \
  --ref 4.3-joycon-fix \
  -f godot_version="4.3.stable"
```

---

## 📋 TODO: Monitor First Build

### Step 6: Watch Build Progress

**GitHub Actions:**
```bash
# Watch via CLI
gh run watch

# Or visit in browser
https://github.com/Nat-Ya/godot-joycon-fix/actions
```

**GCP Cloud Build Console:**
```bash
# List recent builds
gcloud builds list --region=europe-west1 --limit=5

# Stream logs for latest build
BUILD_ID=$(gcloud builds list --region=europe-west1 --limit=1 --format="value(id)")
gcloud builds log $BUILD_ID --region=europe-west1 --stream

# Or visit in browser
https://console.cloud.google.com/cloud-build/builds?region=europe-west1&project=general-476320
```

**Expected build time:** 60-120 minutes with E2_STANDARD_2 (first build is slowest)

---

## 📋 TODO: Verify Build Outputs

### Step 7: Check Build Artifacts

**Docker Image in Artifact Registry:**
```bash
# List images
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix

# Pull image
docker pull europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix:4.3-joycon-fix

# Test image
docker run --rm europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix:4.3-joycon-fix \
  /opt/godot/bin/godot.linuxbsd.editor.x86_64 --version
```

**APKs in Cloud Storage:**
```bash
# List APKs
gsutil ls -lh gs://general-476320_cloudbuild/godot-joycon-fix/4.3-joycon-fix/

# Download latest debug APK
SHORT_SHA=$(git rev-parse --short HEAD)
gsutil cp gs://general-476320_cloudbuild/godot-joycon-fix/4.3-joycon-fix/${SHORT_SHA}/android_debug.apk ./

# Install to device
adb install -r android_debug.apk
```

**GitHub Actions Artifacts:**
```bash
# Download via CLI
gh run download

# Or download from GitHub UI
# Go to: Actions → Latest run → Artifacts section
```

---

## 📋 Troubleshooting Guide

### Issue: "Permission Denied" during build

**Solution:**
```bash
# Check service account has all required roles
gcloud projects get-iam-policy general-476320 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:nys-godot-game-builder@*"

# Re-grant permissions if needed (see Step 2)
```

### Issue: "API not enabled"

**Solution:**
```bash
# Enable all required APIs
gcloud services enable cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  --project=general-476320
```

### Issue: "Bucket not found"

**Solution:**
```bash
# Create bucket
gsutil mb -p general-476320 -l europe-west1 gs://general-476320_cloudbuild/
```

### Issue: "GitHub secret not found"

**Solution:**
- Go to repo Settings → Secrets and variables → Actions
- Verify all 4 secrets are added
- Secret names are case-sensitive!

### Issue: Build timeout (>2 hours)

**Solution:** Increase timeout in `cloudbuild.yaml`:
```yaml
timeout: 10800s  # 3 hours
```

---

## 📋 Post-Setup: Regular Usage

### Daily Development Workflow

```bash
# 1. Make code changes
vim platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java

# 2. Commit changes
git add -A
git commit -m "fix: your changes"

# 3. Push to trigger auto-build
git push origin 4.3-joycon-fix

# 4. Wait for build (30-60 min)
gh run watch

# 5. Download APK when done
SHORT_SHA=$(git rev-parse --short HEAD)
gsutil cp gs://general-476320_cloudbuild/godot-joycon-fix/4.3-joycon-fix/${SHORT_SHA}/android_debug.apk ./

# 6. Test on device
adb install -r android_debug.apk
```

### Quick Local Test (before pushing)

```bash
# Test build locally first (faster iteration)
docker build -t godot-test:local .

# Extract APK
docker cp $(docker create godot-test:local):/root/.local/share/godot/export_templates/4.3.stable/android_debug.apk ./

# Test on device
adb install -r android_debug.apk

# If works, push to trigger Cloud Build for final artifact
git push origin 4.3-joycon-fix
```

---

## 📋 Cost Management

### Monitor Build Costs

```bash
# View Cloud Build usage
gcloud builds list --region=europe-west1 --limit=20 --format="table(id,createTime,duration,status)"

# Estimate costs
# - E2_STANDARD_2: Free tier (120 build-minutes/day free)
# - Builds beyond free tier: ~$0.003/minute
# - Storage: ~$0.02/GB/month
# - Artifact Registry: ~$0.10/GB/month
```

### Cleanup Old Artifacts

```bash
# Delete old Docker images (keep only latest 5)
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/general-476320/android-build-images/godot-joycon-fix \
  --include-tags \
  --format="value(package)" | tail -n +6 | xargs -I {} \
  gcloud artifacts docker images delete {} --delete-tags --quiet

# Delete old APKs (older than 30 days via lifecycle policy - already set)
# Manual cleanup:
gsutil -m rm -r gs://general-476320_cloudbuild/godot-joycon-fix/*/$(date -d '30 days ago' +%Y-%m-%d)
```

---

## 📊 Success Criteria

✅ **Setup is complete when:**

- [ ] All 4 GitHub secrets added
- [ ] Service account has all 4 IAM roles
- [ ] All GCP APIs enabled
- [ ] GCS bucket created
- [ ] First build completes successfully
- [ ] Docker image appears in Artifact Registry
- [ ] APKs stored in GCS bucket
- [ ] APK downloads and installs on device
- [ ] Phase 1 diagnostic logs appear in logcat

**First build success indicators:**
1. GitHub Actions workflow shows green checkmark
2. Cloud Build shows "SUCCESS" status
3. Docker image pullable from Artifact Registry
4. APK downloads from GCS without errors
5. APK installs and runs on Android device

---

## 🎯 Next Phase: Phase 1 Testing

Once build setup is complete:

1. **Install APK with Phase 1 diagnostics**
2. **Test with Joy-Con L**
3. **Capture logs:**
   ```bash
   adb logcat | grep -E "\[Phase1\]|GodotInputHandler"
   ```
4. **Compare L button vs D-pad logs**
5. **Identify failure scenario (A/B/C/D)**
6. **Proceed to Phase 2 fixes**

See `GODOT_FORK_TASKS.md` for Phase 1 testing details.
