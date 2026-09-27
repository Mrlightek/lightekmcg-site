#!/usr/bin/env bash
set -euo pipefail
ruby -ropenssl -rbase64 -e 'puts Base64.strict_encode64(OpenSSL::Random.random_bytes(32))'
