<div align="center">
  <img alt="Starknet Logo" src="assets/starknet-dark.png">

  [![License: Apache2.0](https://img.shields.io/badge/License-Apache2.0-green.svg)](LICENSE)
</div>

# Token Migration Contract

$\color{red}\textbf{Diclaimer:}\text{ This repo is a work in progress. It is not yet tested / audited.}$
$\color{red}\text{Both the API and the implementation are still subject to changes.}$


## Content

- [Overview](#overview)
- [API Reference](#api-reference)
- [Dependencies](#dependencies)
- [Deployment](#deployment)
- [Getting help](#getting-help)
- [Build and Test](#build-and-test)
- [Audit](#audit)
- [Security](#security)

## Overview

This contract aims to aid starknet users in migrating their USDC.e tokens into USDC without having to withdraw them on L1 themselves.

## API Reference
- `swap_to_new(amount: u256)` - Exchange legacy tokens for new ones (1:1 ratio).
  - Precondition: sufficient allowance for the legacy token.
- `swap_to_legacy(amount: u256)` - Exchange new tokens for legacy ones (1:1 ratio).
  - Precondition: sufficient allowance for the new token.

## Dependencies

- Cairo dependencies such as [Scarb](https://docs.swmansion.com/scarb/) and [Starknet foundry](https://foundry-rs.github.io/starknet-foundry/index.html) - install using [starkup](https://github.com/software-mansion/starkup).

## Deployment

Declare and deploy the `TokenMigration` contract on Starknet.

## Getting help

Reach out to the maintainer at any of the following:

- [GitHub Discussions](discussions)
- Contact options listed on this [GitHub profile](https://github.com/starkware-libs)

## Build and Test

Build the contracts from the repo root:

```bash
scarb build
```

To run the tests, execute:

```bash
scarb test
```

## Audit

Find the latest audit report in [docs/audit](docs/audit).

## Security

This repo follows good practices of security, but 100% security cannot be assured. This repo is provided "as is" without any warranty. Use at your own risk.

For more information and to report security issues, please refer to our [security documentation](docs/SECURITY.md).
