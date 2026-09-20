#!/usr/bin/env bash
# Deploy only Koofy Reader. Does not modify Quiz_Site or Slime authentication.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--apply" ]]; then
  printf '%s\n' 'Usage: tool/deploy_reader_backend.sh --apply' 'Requires authenticated gcloud/Firebase CLI, Node 22 and Firebase CLI 15+.'
  exit 2
fi
reader_project='koofy-reader'
reader_account="koofy-reader-api@${reader_project}.iam.gserviceaccount.com"
reader_bucket='gs://koofy-reader.firebasestorage.app'
# A newly created service account can take time to propagate to Storage/IAM.
reader_retry() {
  local reader_attempt=1
  until "$@"; do
    if (( reader_attempt >= 5 )); then return 1; fi
    sleep "$((reader_attempt * 5))"
    reader_attempt=$((reader_attempt + 1))
  done
}
command -v gcloud >/dev/null
command -v firebase >/dev/null
node -e 'if (Number(process.versions.node.split(".")[0]) !== 22) throw Error("Use Node.js 22 to deploy")'
npm --prefix functions test
# Enable only the services used by Firebase's second-generation deployment.
gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com run.googleapis.com iam.googleapis.com \
  iamcredentials.googleapis.com firestore.googleapis.com firebaserules.googleapis.com \
  firebasestorage.googleapis.com storage.googleapis.com --project="$reader_project" --quiet
reader_existing_account="$(gcloud iam service-accounts list --project="$reader_project" --filter="email=$reader_account" --format='value(email)' --quiet)"
if [[ "$reader_existing_account" != "$reader_account" ]]; then
  gcloud iam service-accounts create koofy-reader-api --display-name='Koofy Reader API' --project="$reader_project" --quiet
fi
reader_retry gcloud projects add-iam-policy-binding "$reader_project" \
  --member="serviceAccount:$reader_account" --role=roles/datastore.user --condition=None --quiet --format='value(version)'
reader_retry gcloud storage buckets add-iam-policy-binding "$reader_bucket" \
  --member="serviceAccount:$reader_account" --role=roles/storage.objectAdmin --quiet --format='value(version)'
# Self-scoped signing permission, not a project-wide token-creator grant.
reader_retry gcloud iam service-accounts add-iam-policy-binding "$reader_account" \
  --member="serviceAccount:$reader_account" --role=roles/iam.serviceAccountTokenCreator \
  --project="$reader_project" --quiet --format='value(version)'
if [[ ! -f functions/.env.koofy-reader ]]; then
  cp functions/.env.example functions/.env.koofy-reader
fi
reader_artifact_policy() {
  firebase functions:artifacts:setpolicy --project "$reader_project" \
    --location asia-northeast3 --days 7 --force --non-interactive
}
reader_deploy_target() {
  local reader_log reader_status
  reader_log="$(mktemp "${TMPDIR:-/tmp}/koofy-reader-deploy.XXXXXX")"
  if firebase deploy --project "$reader_project" --only "$1" --non-interactive 2>&1 | tee "$reader_log"; then
    rm -f "$reader_log"
    return 0
  else
    reader_status=$?
  fi
  # CLI can return nonzero after successful first deployment solely because
  # no image retention policy exists. Handle that exact case, not other errors.
  if grep -Fq 'Functions successfully deployed but could not set up cleanup policy' "$reader_log"; then
    rm -f "$reader_log"
    reader_artifact_policy
    return $?
  fi
  rm -f "$reader_log"
  return "$reader_status"
}
reader_deploy_target firestore,storage
# Sequential first creation avoids racing on the region's shared source bucket.
reader_deploy_target functions:reader:readerCatalog
reader_deploy_target functions:reader:readerAdmin
reader_artifact_policy
node tool/verify_reader_backend.mjs
