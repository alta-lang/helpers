# Alta Helpers
Various helper components for different aspects of Alta development.

## Helpers

### `Get-AltaCompiler` Script
This little PowerShell Core script provides a function with the same name to easily download the Alta compiler for any supported system.

Its intended usage is in Continuous Integration (CI) builds (a.k.a. build servers) for projects written in Alta, but it can be used in general just to get a portable copy of the Alta compiler.

### `Test-AltaCompiler` Script
This PowerShell Core script provides a function with the same name to check if the Alta compiler is installed and, optionally, if it matches a given version.

It is intended to be used in conjunction with `Get-AltaCompiler` by first using `Test-AltaCompiler` to check if the necessary version of the Alta compiler is already installed and, if not, downloading to a local directory with `Get-AltaCompiler` and using that.
