#!/usr/bin/env bash

yarn deploy FundCurvePoolScript $@
yarn deploy SeedCurveSwapsScript $@
yarn deploy FundAccountWithUsd0Script $@
yarn deploy FundAccountWithUsd0PPScript $@
yarn deploy SeedRWARedeemsScript $@
