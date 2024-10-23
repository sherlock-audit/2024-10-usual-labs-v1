# Usual Money Monorepository (pegasus)

![Usual Money](./docs/banner.jpg)

![Front Last PR Check](https://github.com/usual-dao/pegasus/actions/workflows/preview.yml/badge.svg)
![Solidity Last PR Check](https://github.com/usual-dao/pegasus/actions/workflows/all.yml/badge.svg)

Usual Money monorepository, contains the smart-contracts, dApp and few services.
Each subpackages contains its own README.

# Subprojects

 - [DApp](./packages/frontend)
 - [Backend services](./packages/subgraph)
 - [Third party actions](./packages/Actions)
 - [Smart-Contracts](./packages/solidity)

# Branches

 - [main](./../../tree/main)
 - [develop](./../../tree/develop)
 - [front/main](./../../tree/front/main)
 - [front/production](./../../tree/front/production)

# External links

 - [DApp tickets](https://linear.app/usual/team/DAPP/cycle/active)
 - [Smart-Contract tickets](https://linear.app/usual/team/PROT/active)
 - [Vercel](https://vercel.com/usual-dao/pegasus)
 - [Sentry](https://usual.sentry.io/projects/)
 - [Tenderly](https://dashboard.tenderly.co/usual/cd/project-dashboard)

# GitHub CI/CD

## Smart-Contract

Composed by GitHub Actions inside reusable workflows.
The `all.yml` workflow is triggered by a GitHub Pull request towards `develop` or `main` branches.

If `reusable-build-lint-test.yml`, `reusable-analysis.yml` and `reusable-spell-check.yml` workflows succeed, the `all.yml` workflow will trigger the `reusable-vercel-deploy.yml` workflow. This workflow will use a build artifact that was created in the previous workflow.
 
## dApp

The `front.yml` workflow will create a Vercel preview and if the PR is targeting `front/production`, the `reusable-vercel-deploy.yml` workflow will adapt to run a production deployment.
