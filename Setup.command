#!/bin/bash
# Double-clickable entry point: opens Terminal and runs the guided setup.
# (If macOS says it "cannot be opened because it is from an unidentified
# developer": right-click this file, choose Open, then Open again.)
cd "$(dirname "$0")"
exec ./setup.sh
