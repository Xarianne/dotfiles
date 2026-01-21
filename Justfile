# JUSTFILE

set shell := ["bash", "-c"]

import ".just/setup.just"
import ".just/maintenance.just"

# Default Menu
_default:
    @just --choose