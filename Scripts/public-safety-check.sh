#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

exclude_args="--glob=!.git/** --glob=!.build/** --glob=!Scripts/public-safety-check.sh"
patterns='(/Users/[A-Za-z0-9._-]+/|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'

# shellcheck disable=SC2086
if rg -n --hidden $exclude_args -e "$patterns" .; then
    printf '%s\n' 'Public-safety check failed: review the matches above.' >&2
    exit 1
fi

printf '%s\n' 'Public-safety check passed.'
