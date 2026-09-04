#!/usr/bin/env bash
# Stamp a development app with the exact repository state used to compile it.

intentive_source_provenance() {
  local repo_root="$1"
  local git_sha source_tree_dirty untracked_inputs

  git_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)" || return 1
  [[ "$git_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  source_tree_dirty=false
  if ! git -C "$repo_root" diff --quiet --ignore-submodules -- \
    || ! git -C "$repo_root" diff --cached --quiet --ignore-submodules --; then
    source_tree_dirty=true
  fi
  untracked_inputs="$(git -C "$repo_root" ls-files --others --exclude-standard)" || return 1
  if [[ -n "$untracked_inputs" ]]; then
    source_tree_dirty=true
  fi
  printf '%s\t%s\n' "$git_sha" "$source_tree_dirty"
}

intentive_stamp_source_provenance() {
  local repo_root="$1"
  local bundle="$2"
  local plist="$bundle/Contents/Info.plist"
  local provenance git_sha source_tree_dirty

  [[ -f "$plist" ]] || return 1
  provenance="$(intentive_source_provenance "$repo_root")" || return 1
  IFS=$'\t' read -r git_sha source_tree_dirty <<<"$provenance"

  /usr/libexec/PlistBuddy -c 'Delete :IntentiveSourceGitSHA' "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :IntentiveSourceGitSHA string $git_sha" "$plist"
  /usr/libexec/PlistBuddy -c 'Delete :IntentiveSourceTreeDirty' "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :IntentiveSourceTreeDirty bool $source_tree_dirty" "$plist"
}
