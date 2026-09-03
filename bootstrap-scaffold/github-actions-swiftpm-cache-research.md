# GitHub Actions SwiftPM cache-key research

**Audited commit:** `4a8e77e713e5f786badac58d7f807e77fe0072ec`

**Audited on:** 2026-09-04

**Scope:** GitHub Actions `hashFiles` and cache restore/save semantics for the
macOS SwiftPM build cache
**External changes made by this research:** none

## Answer

The cache invalidation change used the wrong resource root. The workflow added
`desktop/macos/Desktop/Resources/**`, but that directory does not exist. The
Swift package declares `path: "Sources"` and processes `Resources`, so the
shipping files are under `desktop/macos/Desktop/Sources/Resources/**`
([Package.swift](../desktop/macos/Desktop/Package.swift#L77-L92)).

GitHub documents that `hashFiles` hashes the set of files matched by its path
patterns, and returns an empty string when no files match
([GitHub expressions reference](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#hashfiles)).
The runner implementation combines all supplied patterns into one glob, then
hashes only the files yielded by that glob; unmatched patterns contribute no
sentinel, path name, or other bytes
([runner argument handling](https://github.com/actions/runner/blob/0b0ac2fdabf53d69add6175026945b8afc8549a5/src/Runner.Worker/Expressions/HashFilesFunction.cs#L95-L123),
[runner hashing loop](https://github.com/actions/runner/blob/0b0ac2fdabf53d69add6175026945b8afc8549a5/src/Misc/expressionFunc/hashFiles/src/hashFiles.ts#L20-L52)).
Therefore, adding one nonexistent resource glob alongside two already matching
package-manifest globs leaves the matched file set unchanged. It is an inference
from the documented algorithm and runner source that the resulting digest also
stays unchanged.

GitHub's cache reference says restore first searches for the exact supplied key,
an exact match restores that cache, and an existing cache's contents cannot be
changed; replacement requires a new key
([GitHub dependency-caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#cache-action-usage)).
The action source correspondingly records the primary key, restores by that key,
and identifies equality with the returned key as an exact hit
([restore implementation](https://github.com/actions/cache/blob/3edfce9056124e459a23f683a21433670d47daca/src/restoreImpl.ts#L32-L83));
after an exact hit, its save path deliberately does not write the cache again
([save implementation](https://github.com/actions/cache/blob/3edfce9056124e459a23f683a21433670d47daca/src/saveImpl.ts#L35-L54)).

## Evidence from this repository

Before the attempted invalidation, hosted job
[`100792218747`](https://github.com/sruj75/knowledge-athlete/actions/runs/33798517476/job/100792218747)
restored the exact SwiftPM key ending in `ecc9b01f...e7652`. After the nonexistent
resource glob was added, hosted job
[`100848643173`](https://github.com/sruj75/knowledge-athlete/actions/runs/33816139985/job/100848643173)
computed and restored that same exact key. That job then found retired assets in
the processed resource bundle under the cached `.build` tree. This is direct
evidence that the intended invalidation did not occur; it is not evidence that
GitHub ignored a correctly rooted resource file.

## Implication for the fix

Use `desktop/macos/Desktop/Sources/Resources/**` in both the restore and save key
expressions, and keep the broad SwiftPM `restore-keys` fallback absent. The
correct glob changes the matched set as resource files change, producing a new
primary key and preventing an exact restore of the immutable stale entry. Add a
contract test that requires this exact rooted glob and rejects the nonexistent
`desktop/macos/Desktop/Resources/**` spelling; checking only for a generic
`Resources/**` substring would allow this failure to recur.
