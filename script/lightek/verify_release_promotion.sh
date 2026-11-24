#!/usr/bin/env bash
set -euo pipefail

required=${LIGHTEK_RELEASE_ASSURANCE_REQUIRED:-}
candidate=${LIGHTEK_RELEASE_ASSURANCE_CANDIDATE_ID:-}

# Gate the first combined MSP tree as soon as it reaches the production workflow.
# The flag also enables the gate for other release profiles.
if [[ -f app/models/it_device_maintenance_action.rb && -f app/services/it_services/enrollment.rb &&
      -f app/models/it_remote_support_session.rb && -f app/services/release_assurance/production_promotion.rb ]]; then
  required=1
  export LIGHTEK_RELEASE_ASSURANCE_PROFILE=msp
fi
if [[ "$required" != 1 && -z "$candidate" ]]; then
  exit 0
fi

[[ "${GITHUB_REF:-}" == refs/heads/main && "${GITHUB_SHA:-}" =~ ^[a-f0-9]{40}$ &&
   "$candidate" =~ ^[1-9][0-9]*$ && "${LIGHTEK_RELEASE_PROMOTION_URL:-}" =~ ^https://[a-zA-Z0-9.-]+/gatekeeper/release-promotion$ &&
   -n "${LIGHTEK_RELEASE_PROMOTION_TOKEN:-}" ]] || { echo 'Release approval configuration is incomplete or the ref is ineligible'; exit 1; }

profile=${LIGHTEK_RELEASE_ASSURANCE_PROFILE:-standard}
[[ "$profile" == standard || "$profile" == msp ]]
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
tree=$(git rev-parse 'HEAD^{tree}')
payload=$(jq -n --arg id "$candidate" --arg sha "$GITHUB_SHA" --arg tree "$tree" --arg profile "$profile" \
  '{candidate_id:$id, production_sha:$sha, tree_sha:$tree, profile:$profile}')
response=$(curl --fail --silent --show-error --proto '=https' --connect-timeout 8 --max-time 90 \
  -H "Authorization: Bearer $LIGHTEK_RELEASE_PROMOTION_TOKEN" -H 'Content-Type: application/json' \
  --data "$payload" "$LIGHTEK_RELEASE_PROMOTION_URL")
printf '%s' "$response" | jq -e --arg id "$candidate" --arg sha "$GITHUB_SHA" --arg tree "$tree" \
  '(.candidate_id|tostring) == $id and .production_sha == $sha and .tree_sha == $tree and
   (.source_sha|test("^[a-f0-9]{40}$")) and (.evidence_digest|test("^[a-f0-9]{64}$"))' >/dev/null
echo "Gatekeeper verified production approval for $GITHUB_SHA"
