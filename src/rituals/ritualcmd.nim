import std/[os, osproc, sequtils, strutils, terminal, strformat]


proc parseArgs(): tuple[dir: string, args: string, plaintext: bool] =
  result.dir = "."
  var forwarded: seq[string]
  var i = 1

  while i <= paramCount():
    let param = paramStr(i)

    if param.startsWith("--dir:"):
      result.dir = param[6..^1]
    elif param == "--plaintext":
      result.plaintext = true
    else:
      forwarded.add param

    inc i

  result.args = forwarded.join(" ")


proc findConfig(dir: string): string =
  var current = dir.absolutePath()

  while true:
    let configPath = current / "ritual.cfg"
    if fileExists(configPath):
      return configPath

    let parent = parentDir(current)
    if parent == current:
      return ""
    current = parent


proc readConfigFlags(configPath: string): string =
  readFile(configPath).splitLines()
    .mapIt(it.strip())
    .filterIt(it.len > 0 and not it.startsWith("#"))
    .join(" ")


proc initWorkspace(dir: string) =
  let root = dir.absolutePath()
  let ritualsPath = root / "rituals" / "src"
  let ritualPaths = walkDir(root)
    .toSeq()
    .filterIt(it.kind == pcDir)
    .filterIt(fileExists(it.path / "ritual.nim"))
    .mapIt(it.path)

  if not dirExists(root / "rituals"):
    styledEcho fgYellow, "Warning: ", resetStyle, "'rituals' repo not found in workspace, add 'rituals' as a dependency or clone it from 'git@github.com:RowDaBoat/rituals.git' into this workspace."

  var config = "--path:" & ritualsPath & "\n"
  for path in ritualPaths:
    config.add "--import:" & path / "ritual.nim" & "\n"

  let configPath = root / "ritual.cfg"
  writeFile(configPath, config)


when isMainModule:
  let (dir, args, plaintext) = parseArgs()

  if args.strip() == "init":
    initWorkspace(dir)
    quit(0)

  let config = findConfig(dir)

  if config.len == 0:
    styledEcho fgRed, "Error: ", resetStyle, "No 'ritual.cfg' found. Run 'ritual init' to create one."
    quit(1)

  let configFlags = readConfigFlags(config)
  let flags = "--verbosity:0 --warnings:off --hints:off --skipParentCfg --skipProjCfg"
  var eval = ""

  if args.strip() == "list":
    eval = "--eval:\"import rituals; listRituals()\""
  else:
    let name = args.strip()
    let packageName = dir.absolutePath.lastPathPart
    let qualifiedName = if '.' in name: name else: &"{packageName}.{name}"
    let ritual = &"\\\"{qualifiedName}\\\""
    var nimCode = "import rituals;"
    nimCode &=   &"runRitual({ritual}, {plaintext})"
    eval = &"--eval:\"{nimCode}\""

  let command = @["nim r", flags, configFlags, eval].join(" ")
  quit(execCmd(command))
