#!/bin/sh

pnpm install --frozen-lockfile --ignore-scripts
pnpm generate
pnpm build
