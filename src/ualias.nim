#TODO Check permission to do all actions
#TODO: Make sure input is clean
#TODO: Rewrite asserts to match style
#TODO: Avoid circular aliases

from os import FilePermission, newOSError, OSErrorCode, joinPath, addFileExt, setFilePermissions, symlinkExists, fileExists, getFilePermissions, walkDir, PathComponent, splitFile, getAppFilename, commandLineParams, expandFilename
from posix import PC_PATH_MAX, realpath, errno, strerror, mkdir, EEXIST, unlink, O_WRONLY, O_CREAT, O_TRUNC, O_EXCL, S_IRWXU, S_IRGRP, S_IXGRP, S_IROTH, S_IXOTH, open, write, symlink, close
from logging import Logger, log, Level, newConsoleLogger
from streams import Stream, openFileStream, close, readLine, peekLine
from strutils import startsWith, endsWith, split, contains, find
from sequtils import toSeq
from algorithm import sorted
from times import now, format

from bwap import newArgsParser, newOptionalPositionalArgs, newOptionalValuedArgs, newHelpArgs, newBoolArgs, parseOptsSeq, getIsSet, getArgsName, getArgsParserDocumentation, getNumValues, getValues, getValue

# Exception type
type AliasError = object of CatchableError
# Exception type end

# Program info and help
type ProgramInfo = ref object of RootObj
  exeName: string
  version: string
  defLinkDir: string
  defStoreDir: string
proc newProgramInfo(exeName, version, defLinkDir, defStoreDir: string): ProgramInfo =
  result = ProgramInfo(exeName: exeName,
                       version: version,
                       defLinkDir: defLinkDir,
                       defStoreDir: defStoreDir)
# End program info and help

# Helpers
const rwxrxrxPerms = {FilePermission.fpUserExec,
                      FilePermission.fpUserRead,
                      FilePermission.fpUserWrite,
                      FilePermission.fpGroupExec,
                      FilePermission.fpGroupRead,
                      FilePermission.fpOthersExec,
                      FilePermission.fpOthersRead}
# End helpers

# Program context
type ProgramContext = ref object of RootObj
  lw: Logger
  info: ProgramInfo
  overwrite: bool
  storeDir: string
  linkDir: string
type PrintMode = enum normal, shell, name
proc getPrintMode(mode: string): PrintMode =
  if mode == "normal":
    result = PrintMode.normal
  elif mode == "shell":
    result = PrintMode.shell
  elif mode == "name":
    result = PrintMode.name
  else:
    assert(false)
type PrintContext = ref object of ProgramContext
  exeName: string
  mode: PrintMode
type TargetedContext = ref object of ProgramContext
  storePath: string
  linkPath: string
  aliasName: string
type CreationContext = ref object of TargetedContext
  aliasTarget: string
  aliasPostInstruction: string
proc initProgramContext(ctx : ProgramContext; lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir: string) =
  let resolvedStoreDir = expandFilename(storeDir)
  let resolvedLinkDir = expandFilename(linkDir)
  ctx.lw = lw
  ctx.info = info
  ctx.overwrite = overwrite
  ctx.storeDir = resolvedStoreDir
  ctx.linkDir = resolvedLinkDir
#proc newProgramContext(lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir: string): ProgramContext =
#  result = new(ProgramContext)
#  initProgramContext(result, lw, info, overwrite, storeDir, linkDir)
proc initPrintContext(ctx : PrintContext; lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, exeName: string, mode: PrintMode) =
  initProgramContext(ctx, lw, info, overwrite, storeDir, linkDir)
  ctx.exeName = exeName
  ctx.mode = mode
proc newPrintContext(lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, exeName: string, mode: string): PrintContext =
  result = new(PrintContext)
  initPrintContext( result, lw, info, overwrite, storeDir, linkDir, exeName, getPrintMode(mode) )
proc initTargetedContext(ctx : TargetedContext; lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, aliasName: string) =
  initProgramContext(ctx, lw, info, overwrite, storeDir, linkDir)
  ctx.storePath = joinPath( ctx.storeDir, addFileExt(aliasName, "sh") )
  ctx.linkPath = joinPath(ctx.linkDir, aliasName)
  ctx.aliasName = aliasName
proc newTargetedContext(lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, aliasName: string): TargetedContext =
  result = new(TargetedContext)
  initTargetedContext(result, lw, info, overwrite, storeDir, linkDir, aliasName)
proc initCreationContext(ctx : CreationContext; lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, aliasName, aliasTarget, aliasPostInstruction: string) =
  initTargetedContext(ctx, lw, info, overwrite, storeDir, linkDir, aliasName)
  ctx.aliasTarget = aliasTarget
  ctx.aliasPostInstruction = aliasPostInstruction
proc newCreationContext(lw : Logger; info: ProgramInfo; overwrite: bool; storeDir, linkDir, aliasName, aliasTarget, aliasPostInstruction: string): CreationContext =
  result = new(CreationContext)
  initCreationContext(result, lw, info, overwrite, storeDir, linkDir, aliasName, aliasTarget, aliasPostInstruction)
# Program context end

# More path helpers
proc safelyCreateDir(lw: Logger; path: string) =
  let ret = mkdir(path, 0o755)
  if ret != 0:
    assert ret == -1
    if errno == EEXIST:
      lw.log(Level.lvlInfo, "Path: '", path, "' already exists.")
    else:
      raise newOSError(cast[OSErrorCode](errno), "Failed to create directory at path '" & path & "' due to '" & $strerror(errno) & "'.")
  else:
    lw.log(Level.lvlInfo, "Successfully created directory at path: '", path, "'.")
# End more path helpers

# Alias checking
type AliasLineNum = range[0..7]

type AliasScanner = ref object of RootObj
  path: string
  s: Stream
  lnum: AliasLineNum
  line: string
  lw: Logger

proc newAliasScanner(lw : Logger; path: string): AliasScanner =
  result = AliasScanner(path: path,
                        s: openFileStream(path),
                        lnum: 0,
                        line: "",
                        lw: lw)

proc closeAliasScanner(scanner: AliasScanner) =
  scanner.s.close()

proc readAliasLine(scanner: AliasScanner) =
  let isNotEof = scanner.s.readLine(scanner.line)
  if not isNotEof:
    raise newException(EOFError, "EOF not expected at line " & $scanner.lnum & " for path '" & scanner.path & "'.")
  else:
    scanner.lnum += 1

type AliasFormatError = object of AliasError

proc buildAliasFormatErrmsg(scanner: AliasScanner; msg: string): string =
  result = "'" & scanner.path & "' line " & $scanner.lnum & ": " & msg

type AliasLineNotEqualError = object of AliasFormatError
proc checkAliasLineEqual(scanner: AliasScanner; equal: string) =
  if scanner.line != equal:
    raise newException( AliasLineNotEqualError, buildAliasFormatErrmsg(scanner, "Expected to equal '" & equal & "'.") )

type AliasLineNotEmptyError = object of AliasFormatError
proc checkAliasLineEmpty(scanner: AliasScanner) =
  if scanner.line != "":
    raise newException( AliasLineNotEmptyError, buildAliasFormatErrmsg(scanner, "Expected to empty.") )

type AliasLineNotStartError = object of AliasFormatError
proc checkAliasLineStart(scanner: AliasScanner; start: string) =
  if not scanner.line.startsWith(start):
    raise newException( AliasLineNotStartError, buildAliasFormatErrmsg(scanner, "Expected to start with '" & start & "'.") )

type AliasLineNotEndError = object of AliasFormatError
proc checkAliasLineEnd(scanner: AliasScanner; lineEnd: string) =
  if not scanner.line.endsWith(lineEnd):
    raise newException( AliasLineNotEndError, buildAliasFormatErrmsg(scanner, "Expected to end with '" & lineEnd & "'.") )

type AliasNotEOFError = object of AliasFormatError
proc checkAliasEOF(scanner: AliasScanner) =
  var tmpString = ""
  let isNotEof = scanner.s.peekLine(tmpString)
  if isNotEof:
    raise newException( AliasNotEOFError, buildAliasFormatErrmsg(scanner, "Alias files should only be " & $high(AliasLineNum) & " lines, but the next line was instead '" & tmpString & "'.") )

type AliasLineNotContainsError = object of AliasFormatError
proc checkAliasLineContains(scanner: AliasScanner; subs: string) =
  if not scanner.line.contains(subs):
    raise newException( AliasLineNotContainsError, buildAliasFormatErrmsg(scanner, "Expected to contain '" & subs & "'.") )

proc checkAliasLineStartEnd(scanner: AliasScanner; start, lineEnd: string) =
  scanner.checkAliasLineStart(start)
  scanner.checkAliasLineEnd(lineEnd)

proc scanAlias(scanner: AliasScanner) =
  scanner.readAliasLine()
  scanner.checkAliasLineEqual("#!/bin/sh -efu")
  scanner.readAliasLine()
  scanner.checkAliasLineEmpty()
  scanner.readAliasLine()
  scanner.checkAliasLineStartEnd("# This script was automatically generated by ualias at '", "'.")
  scanner.readAliasLine()
  scanner.checkAliasLineStart("# VERSION: ")
  scanner.readAliasLine()
  if scanner.line.startsWith("# DATE: "):
    scanner.readAliasLine()
  scanner.checkAliasLineEmpty()
  scanner.readAliasLine()
  scanner.checkAliasLineContains(" \"$@\" ")
  scanner.checkAliasLineEnd(" # ALIASED")
  scanner.checkAliasEOF()
# Alias checking end

# Alias deletion
proc performDelete(lw: Logger; name: string) =
  let ret = unlink(name)
  if ret != 0:
    raise newOSError(cast[OSErrorCode](errno), "Failed to delete '" & name & "'.")
  else:
    lw.log(Level.lvlInfo, "Successfully deleted '", name, "'.")

proc removeAlias(ctx: TargetedContext) =
  let resolvedLinkPath = expandFilename(ctx.linkPath)
  if ctx.storePath != resolvedLinkPath:
    raise newException(OSError, "'" & ctx.linkPath & "' does not resolve to the same target as '" & ctx.storePath & "'.")
  else:
    assert symlinkExists(ctx.linkPath)
    assert fileExists(resolvedLinkPath)
    let scanner = newAliasScanner(ctx.lw, resolvedLinkPath)
    try:
      scanner.scanAlias()
      if rwxrxrxPerms != getFilePermissions(ctx.linkPath):
        raise newException(OSError, "'" & ctx.linkPath & "' does not have 755 permissions.")
      if rwxrxrxPerms != getFilePermissions(resolvedLinkPath):
        raise newException(OSError, "'" & resolvedLinkPath & "' does not have 755 permissions.")
      performDelete(ctx.lw, ctx.linkPath)
      performDelete(ctx.lw, resolvedLinkPath)
    finally:
      closeAliasScanner(scanner)
# Alias deletion end

# Alias creation
proc createAlias(ctx: CreationContext) =
  if ctx.overwrite and fileExists(ctx.linkPath): #TODO: Message about link path not existing?
    removeAlias(ctx)
  let outputHandle = open(ctx.storePath.cstring, O_WRONLY or O_CREAT or O_TRUNC or O_EXCL, S_IRWXU or S_IRGRP or S_IXGRP or S_IROTH or S_IXOTH)
  if outputHandle == -1:
    raise newOSError(cast[OSErrorCode](errno), "Failed to create alias script at '" & ctx.storePath & "' due to '" & $strerror(errno) & "'.")
  try:
    ctx.lw.log(Level.lvlInfo, "Successfully created alias script at '", ctx.storePath, "'.")
    setFilePermissions(ctx.storePath, rwxrxrxPerms) #TODO: For some reason, open doesn't always seem to do this. Especially not when running root, and I wonder if it's due to the normal shell settings of the user.
    ctx.lw.log(Level.lvlInfo, "Successfully set permissions to 755 for '", ctx.storePath, "'.")
    var aliasSpace = ""
    if ctx.aliasPostInstruction != "":
      aliasSpace = " "
    let contentsTarget = ctx.aliasTarget & " \"$@\" " & ctx.aliasPostInstruction & aliasSpace & "# ALIASED"
    let contents = "#!/bin/sh -efu\n" &
                   "\n" &
                   "# This script was automatically generated by ualias at '" & ctx.info.exeName & "'.\n" &
                   "# VERSION: " & ctx.info.version & "\n" &
                   "# DATE: " & now().format("yyyy-MM-dd'_'HH:mm:ssZZZ") & "\n" &
                   "\n" &
                   contentsTarget & "\n"
    let writeLen = write( outputHandle, contents.cstring, len(contents) )
    if writeLen != len(contents):
      raise newOSError(cast[OSErrorCode](errno), "Only able to write " & $writeLen & " bytes to alias script at '" & ctx.storePath & "' due to '" & $strerror(errno) & "'.")
    ctx.lw.log(Level.lvlInfo, "Successfully wrote alias contents of ", $writeLen, " bytes to '", ctx.storePath, "':")
    ctx.lw.log(Level.lvlInfo, ctx.aliasName, "=\"", contentsTarget, "\"")
    let symlinkRes = symlink(ctx.storePath.cstring, ctx.linkPath.cstring)
    if symlinkRes != 0:
      raise newOSError(cast[OSErrorCode](errno), "Unable to symlink '" & ctx.storePath & "' to '" & ctx.linkPath & "' due to '" & $strerror(errno) & "'.")
    ctx.lw.log(Level.lvlInfo, "Successfully symlinked '", ctx.storePath, "' to '", ctx.linkPath, "'.")
  finally:
    let closeRes = close(outputHandle)
    if closeRes != 0:
      assert(closeRes == -1)
      raise newOSError(cast[OSErrorCode](errno), "Failed to close alias script at '" & ctx.storePath & "' due to '" & $strerror(errno) & "'.")
    ctx.lw.log(Level.lvlInfo, "Successfully closed alias script at '", ctx.storePath, "'.")
# Alias creation end

# Alias printing
proc printAliasPretext(ctx: PrintContext) =
  if ctx.mode == PrintMode.shell:
    stdout.writeLine("#!/bin/sh -efu")
    stdout.writeLine("")
proc printAliasPosttext(ctx: PrintContext) =
  if ctx.mode == PrintMode.name:
    stdout.writeLine("")
proc getEscaped(value: string, toEscape: openArray[string], escapeWith: string): string =
  result = ""
  var idx: Natural = 0
  while idx < len(value):
    var escaped: bool = false
    let currentValue = value[idx..value.high]
    for e in toEscape:
      if currentValue.startsWith(e):
        result &= (escapeWith & e)
        idx += len(e)
        escaped = true
        break
    if not escaped:
      result &= value[idx]
      idx += 1
proc getShellEscaped(value: string): string =
  result = getEscaped(value, ["$", "`", "\\", "\""], "\\")

proc formatAliasEntry(ctx: PrintContext; aliasName: string; scanner: AliasScanner): string =
  if ctx.mode == PrintMode.name:
    result = aliasName & " "
  else:
    var aliasContents: string
    var aliasPostInstruction: string = ""
    if scanner.line.endsWith(" \"$@\" # ALIASED"):
      aliasContents = scanner.line[0..len(scanner.line) - len(" \"$@\" # ALIASED") - 1]
    elif scanner.line.endsWith(" # ALIASED"):
      aliasContents = scanner.line[0..len(scanner.line) - len(" # ALIASED") - 1]
      let aliasPostInstructionArgsStart = aliasContents.find("\"$@\" ")
      let aliasPostInstructionStart = aliasPostInstructionArgsStart + len("\"$@\" ")
      assert(aliasPostInstructionStart >= 0)
      aliasPostInstruction = aliasContents[aliasPostInstructionStart..len(aliasContents) - 1]
      aliasContents = aliasContents[0..aliasPostInstructionArgsStart - 2]
    if ctx.mode == PrintMode.normal:
      var aliasSpace = ""
      if aliasPostInstruction != "":
        aliasSpace = " \"$@\" "
      result = aliasName & "=\"" & aliasContents & aliasSpace & aliasPostInstruction & "\"" & "\n"
    elif ctx.mode == PrintMode.shell:
      result = getShellEscaped(ctx.exeName) &
               " --verbose --overwrite --scripts-dir \"" &
               getShellEscaped(ctx.storeDir) &
               "\" --link-dir \"" &
               getShellEscaped(ctx.linkDir) &
               "\" \"" &
               getShellEscaped(aliasName) &
               "\" \"" &
               getShellEscaped(aliasContents) &
               "\""
      if aliasPostInstruction != "":
        result &= " --post-instruction \"" & getShellEscaped(aliasPostInstruction) & "\""
      result &= "\n"

proc printAliases(ctx: PrintContext) =
  printAliasPretext(ctx)
  for f in sorted( toSeq( walkDir(ctx.storeDir, false, true) ) ):
    let kind = f.kind
    let path = f.path
    #TODO: More messages for continues?
    if kind != PathComponent.pcFile:
      continue
    let aliasName = splitFile(path).name
    let aliasPath = joinPath(ctx.linkDir, aliasName)
    if not symlinkExists(aliasPath):
      continue
    var resolvedAliasPath = ""
    try:
      resolvedAliasPath = expandFilename(aliasPath)
    except:
      ctx.lw.log(Level.lvlWarn, "'", aliasPath, "' formed from '", path, "' cannot be resolved.")
      continue
    if resolvedAliasPath != path:
      ctx.lw.log(Level.lvlWarn, "'", aliasPath, "' does not resolve to '", path, "'.")
      continue
    if rwxrxrxPerms != getFilePermissions(path):
      #TODO: Specify alias name here and above?
      ctx.lw.log(Level.lvlWarn, "'", path, "' pointed to by '", aliasPath, "' does not have 755 file permissions.")
      continue
    let scanner = newAliasScanner(ctx.lw, path)
    try:
      scanner.scanAlias()
      stdout.write( formatAliasEntry(ctx, aliasName, scanner) )
    except AliasFormatError:
      ctx.lw.log(Level.lvlWarn, "'", path, "' is not recognized as a ualias script.")
    finally:
      closeAliasScanner(scanner)
      #TODO: Make sure this closes
  printAliasPosttext(ctx)
# Alias printing end

# Main
type AliasUsageError = object of AliasError
when isMainModule:
  let info = newProgramInfo(getAppFilename(),
                            "2023-09-04-NIM",
                            "/usr/local/bin",
                            "/usr/local/bin/aliases")
  var ap = newArgsParser(info.exeName, "Manage shell-script based aliases. (Version " & info.version & ")")
  var apPos = ap.newOptionalPositionalArgs("Leave the positional args blank to print aliases. Otherwise, to create aliases, valid formats are \"<Alias Name>=<Alias Contents>\" and \"<Alias Name> <Alias Contents>\".", mostArgs = 2)
  var apDelete = ap.newOptionalValuedArgs("delete", 'd', "Delete the specified alias. No positional options may be used when this is specified.")
  var apPostInstruction = ap.newOptionalValuedArgs("post-instruction", 'p', "When creating an alias, this is to be included after the arguments.")
  var apPrintFormat = ap.newOptionalValuedArgs("print-format", 'P', "The format to print aliases in.", defaultArg = "normal", argChoices = ["normal", "shell", "name"])
  var apHelp = ap.newHelpArgs("help", 'h', "Print help, then quit.")
  var apVerbose = ap.newBoolArgs("verbose", 'v', "Print non-error messages to stderr.")
  var apOverwrite = ap.newBoolArgs("overwrite", 'o', "Overwrite the alias if it already exists.")
  var apScriptsDir = ap.newOptionalValuedArgs("scripts-dir", 's', "Choose where alias scripts are stored.", defaultArg = info.defStoreDir)
  var apLinkDir = ap.newOptionalValuedArgs("link-dir", 'l', "Choose where alias scripts are linked to. This should probably be an executable path.", defaultArg = info.defLinkDir)
  ap.parseOptsSeq( commandLineParams() )

  if apDelete.getIsSet() and apPos.getIsSet():
    raise newException(AliasUsageError, "Positional args may not be specified when deleting aliases using '" & apDelete.getArgsName() & "'.")

  var logThreshold = lvlWarn
  if apVerbose.getIsSet():
    logThreshold = lvlAll
  let lw = newConsoleLogger(logThreshold, "$levelname:", true)

  if apHelp.getIsSet():
    stderr.write( ap.getArgsParserDocumentation() )
  elif apDelete.getIsSet():
    removeAlias( newTargetedContext( lw, info, apOverwrite.getIsSet(), apScriptsDir.getValue(), apLinkDir.getValue(), apDelete.getValue() ) )
  elif not apPos.getIsSet():
    printAliases( newPrintContext( lw, info, apOverwrite.getIsSet(), apScriptsDir.getValue(), apLinkDir.getValue(), info.exeName, apPrintFormat.getValue() ) )
  else:
    var aliasName = ""
    var aliasTarget = ""
    if apPos.getNumValues() == 1:
      let aliasParts = apPos.getValues()[0].split('=', 1)
      if len(aliasParts) < 2:
        raise newException(AliasUsageError, "Single string aliases must follow the format of (including the '='): <Alias Name>=<Alias Contents>.")
      aliasName = aliasParts[0]
      aliasTarget = aliasParts[1]
    else:
      assert(apPos.getNumValues() == 2)
      let values = apPos.getValues()
      aliasName = values[0]
      aliasTarget = values[1]
    if aliasName.contains("/"):
      raise newException(AliasUsageError, "Alias names may not contain '/'.")
    safelyCreateDir( lw, apLinkDir.getValue() )
    safelyCreateDir( lw, apScriptsDir.getValue() )
    let ctx = newCreationContext( lw, info, apOverwrite.getIsSet(), apScriptsDir.getValue(), apLinkDir.getValue(), aliasName, aliasTarget, apPostInstruction.getValue() )
    createAlias(ctx)
# Main end
