UAlias
======

Overview and Usage
------------------

'**U**niversal**Alias**'. Like the common `alias` builtin for most shells, but it generates a standalone, POSIX-compliant shell script. (The generated code has been tested with the dash shell.)

### File Locations ###

By default, the scripts themselves are stored in an `aliases` directory in `/usr/local/bin`, and each script therein is symbolically linked to the parent directory without an extension, so it may be called normally as a command assuming it's in the executable path. This behavior may be overriden with the `--link-dir` and `--scripts-dir` options. Defaults may be changed by rebuilding UAlias. No databases, no configuration.

### Script Generation ###

Scripts may be generated with a similar command to the usual `alias` builtin: Either `ualias <name> <contents>` or `ualias <name>=<contents>`. They may be deleted with `ualias -d <name>`. Additionally, `--post-instruction` flag may be included to place code after the parameters of a script, instead of before.

### Script Display ###

When invoked alone, `ualias` will print the scripts in `--scripts-dir` in a familiar format. UAlias also supports different output formats. For instance, `ualias -P shell` will instead print a shell script containing UAlias commands necessary to overwrite reproduce the currently stored aliases. It may be edited then invoked to change many aliases at once.

#### Improving Performance ####

The read performance of UAlias may be improved by placing it in a cron job that runs periodically and pipes its output into `/dev/null`. (Example: `@hourly ualias > /dev/null`). This will help to keep the script files in the operating system's read cache

Building
--------

UAlias requires [bwap](https://github.com/buzzingwires/bwap)

Run `nimble install https://github.com/buzzingwires/bwap` to install.

Then ualias can be built with `nimble build`. Copy the resulting binary wherever you'd like.
