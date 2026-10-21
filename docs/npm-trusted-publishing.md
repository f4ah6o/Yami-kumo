# npm Trusted Publishing

The `npm trusted publishing` workflow (`.github/workflows/npm-publish.yml`)
prepares `@f4ah6o/yami-kumo` from a manually selected **main** revision.
It defaults to validation only. Pushes, tags and pull requests never publish.
The current release policy accepts only `X.Y.Z-preview.N` and uses `preview`.
The private root manifest and Mooncakes releases are independent.

## One-time setup

1. Merge the workflow and run it from `main` with `version` equal to
   `npm/package.json` (`0.1.0-preview.1` currently), leaving `publish` unchecked.
   Download `npm-release` and inspect its tarball, manifest, `BUILD.json`, licenses
   and `npm-consumers.json`. Confirm the source revision and CI/review results.
2. Confirm ownership of the npm `@f4ah6o` scope using an authenticated maintainer
   account. An unauthenticated registry lookup returned E404 on 2026-10-20;
   existence and ownership are not established by this preparation.
   If the package does not exist, bootstrap its first version interactively
   from that reviewed tarball using `npm login`, then
   `npm publish ./f4ah6o-yami-kumo-0.1.0-preview.1.tgz --access public --tag preview --ignore-scripts`.
   This is a separate release action, not performed by this preparation.
   After bootstrap, bump `npm/package.json` to an unused preview version in a PR.
   An already published version cannot be published again.
3. Create a GitHub environment named `npm` in this repository. Restrict its
   deployment branch to `main`; configure required reviewers if desired.
4. In npm package Settings → Trusted Publisher, choose GitHub Actions and enter:

   | Field                | Exact value                 |
   | -------------------- | --------------------------- |
   | Organization or user | `f4ah6o`                    |
   | Repository           | `Yami-kumo`                 |
   | Workflow filename    | `npm-publish.yml`           |
   | Environment name     | `npm`                       |
   | Allowed actions      | Enable direct `npm publish` |

   Enter the filename only, not `.github/workflows/…`. No `NPM_TOKEN` or
   `NODE_AUTH_TOKEN` secret is needed. Do not add a token fallback.

## Release

1. Update the explicit preview version in `npm/package.json` and merge reviewed
   changes after CI succeeds. Run `npm trusted publishing` from `main` with the
   exact version and `publish=false` to inspect a candidate.
2. Run it again on the reviewed main revision with `publish=true`. Each run
   rebuilds and tests its own artifact. The prepare job runs isolated JS, TS,
   browser and React consumers and `npm publish --dry-run`. The publish job
   downloads that run's exact tarball and verifies its hashes, complete consumer
   evidence, packed manifest, clean build and source SHA before `npm publish`.
   Only the publish job receives `id-token: write` and uses environment `npm`.
3. Inspect the npm version and its provenance. Install the exact registry version
   into a clean consumer project and rerun the relevant consumer smoke tests.
   Registry-installed acceptance remains unverified until this step is performed.

Both jobs use GitHub-hosted Ubuntu. Node 24 and npm 11.9.0 in the publish job
meet npm's OIDC minimum (Node 22.14.0 and npm 11.5.1). npm generates provenance
automatically for trusted publishing. `publish=false` does not test npm OIDC
authentication or confirm package ownership.

## Failure handling

1. Version/source/evidence mismatch: correct the manifest or dispatch inputs and
   rerun from main. Do not replace the downloaded tarball by rebuilding in the
   publish job.
2. npm E404 while publishing: check package ownership and all four trusted
   publisher identity fields, direct-publish permission and npm version.
3. Already published version: bump to a new version through review. A failed
   post-publication verification does not imply the release was rolled back.

References: [npm trusted publishers](https://docs.npmjs.com/trusted-publishers/),
[npm provenance](https://docs.npmjs.com/generating-provenance-statements/).
