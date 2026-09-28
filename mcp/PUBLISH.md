# Publish the MCP package

PLAN-NEXT.md item 1 is still pending. On 2026-09-12 the public npm registry
returned 404 for `@alanshurafa/co-evolution-mcp`, `npm whoami` returned 401,
and the repository had no Actions secrets configured. Authenticate npm with
an account that can publish to the `@alanshurafa` scope before continuing.
Do not put credentials in this repository.

The existing tag workflow uses the repository's `NPM_TOKEN` secret. For a
manual release, run the following from `mcp/` after choosing the release
version corresponding to the source tag:

```bash
npm version --no-git-tag-version <release-version>
npm pack --pack-destination ../runs/
npm publish ../runs/alanshurafa-co-evolution-mcp-<release-version>.tgz --access public
```

`npm pack` vendors the source and compiles TypeScript through `prepack`.
The tarball is the release artifact; publishing it does not invoke the build
again. Commit the version and lockfile with a TypeScript check before tagging
the source. Choose either manual publication or the tag workflow for a release.

After publication, install the registry package:

```bash
npm install -g @alanshurafa/co-evolution-mcp
```

Configure Claude Desktop, Cursor, or Continue using the examples in README.md,
then call `co_evolve` once on a disposable markdown document with an absolute
path and `runs_dir` pointing into this checkout's `runs/` directory. On Windows,
ensure Git for Windows' `bin` directory precedes the Windows WSL bash launcher
on the client's PATH. Record the client response and artifact directory.

For the current usability goal, item 1 is done when the registry install works
and `co-evolve --help` prints usage. The external MCP call above is an additional
integration exercise. A local tarball does not establish registry availability.
Run the test suite once when the item is complete;
judge execution, behavior-score gates, and extra verification loops are not
part of this release procedure.
