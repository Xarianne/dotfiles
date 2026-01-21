# JUSTFILE

set shell := ["bash", "-c"]

# QUOTES ARE REQUIRED HERE
import ".just/setup.just"
import ".just/maintenance.just"

# Default Menu
default:
    @just --choose