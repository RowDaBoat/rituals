import std/os
when defined(windows):
  import std/winlean
else:
  import std/terminal
import rituals


type InstallTarget = enum
  Nimby
  Nimble
  Skip

type Key = enum
  Up
  Down
  Enter
  Other


let ritualBin = addFileExt("ritual", ExeExt)
let nimbyBinPath = "~/.nimby/nim/bin".expandTilde
let nimbleBinPath = "~/.nimble/bin".expandTilde


proc readKey(): Key =
  when defined(windows):
    let fd = getStdHandle(STD_INPUT_HANDLE)
    var keyEvent = KEY_EVENT_RECORD()
    var numRead: cint
    while true:
      doAssert(waitForSingleObject(fd, INFINITE) == WAIT_OBJECT_0)
      doAssert(readConsoleInput(fd, addr(keyEvent), 1, addr(numRead)) != 0)
      if numRead == 0 or keyEvent.eventType != 1 or keyEvent.bKeyDown == 0:
        continue
      case keyEvent.wVirtualKeyCode
      of 0x26: return Up
      of 0x28: return Down
      of 0x0D: return Enter
      else: return Other
  else:
    case getch()
    of '\e':
      if getch() == '[':
        case getch()
        of 'A': return Up
        of 'B': return Down
        else: return Other
      else:
        return Other
    of '\r', '\n':
      return Enter
    else:
      return Other


proc renderOptions(options: openArray[string], selected: int) =
  for index, name in options:
    let isSelected = index == selected
    let rune = if isSelected: "\e[38;5;196m●\e[0m" else: "\e[38;5;236m◌\e[0m"
    let color = if isSelected: "\e[38;5;231m" else: "\e[38;5;240m"
    stdout.write "  " & rune & " " & color & name & "\e[0m\n"
  stdout.flushFile()


proc clearOptions(count: int) =
  for i in 0 ..< count:
    stdout.write "\e[1A\e[2K"
  stdout.write "\r"
  stdout.flushFile()


proc promptTarget(): InstallTarget =
  let options = ["Nimby  (~/.nimby/nim/bin)", "Nimble (~/.nimble/bin)", "Skip"]
  var selected = 0

  stdout.write "\e[?25l"
  stdout.write "Install location:\n"
  renderOptions(options, selected)

  while true:
    case readKey()
    of Up:
      selected = (selected - 1 + options.len) mod options.len
    of Down:
      selected = (selected + 1) mod options.len
    of Enter:
      break
    of Other:
      discard

    clearOptions(options.len)
    renderOptions(options, selected)

  clearOptions(options.len)
  stdout.write "\e[1A\e[2K"
  stdout.write "Install location: " & options[selected] & "\n"
  stdout.write "\e[?25h"
  stdout.flushFile()

  InstallTarget(selected)


let target = promptTarget()


ritual "install-ritual":
  nim.compile("src/rituals/ritualcmd.nim", "-o:" & ritualBin)

  case target
  of Nimby:
    mkdir(nimbyBinPath)
    move(ritualBin, nimbyBinPath / ritualBin)
  of Nimble:
    mkdir(nimbleBinPath)
    move(ritualBin, nimbleBinPath / ritualBin)
  of Skip:
    notice("Skipped installation")


runRitual("rituals.install-ritual")
