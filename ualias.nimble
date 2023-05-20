# Package

version       = "1.0.0"
author        = "buzzingwires"
description   = "Create standalone shell scripts from aliases"
license       = "GPL-3.0-only"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.12"
requires "bwap >= 1.0.0"


# Targets

bin = @["ualias"]
