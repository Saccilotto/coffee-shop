#!/bin/bash
# Hook ApplicationStart
set -euo pipefail

systemctl enable coffee-api.service
systemctl restart coffee-api.service
