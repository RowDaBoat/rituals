import std/strutils

when defined(windows):
  import std/winlean

  const enableVirtualTerminalProcessing = 0x0004'i32

  proc getConsoleMode(handle: Handle, mode: ptr DWORD): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(handle: Handle, mode: DWORD): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

  proc enableAnsi*(): bool =
    let handle = getStdHandle(STD_OUTPUT_HANDLE)
    var mode: DWORD
    if getConsoleMode(handle, addr mode) == 0:
      return false
    setConsoleMode(handle, mode or enableVirtualTerminalProcessing) != 0
else:
  proc enableAnsi*(): bool = true

const reset*      = "\e[0m"
const eraseLine*  = "\e[2K"
const hideCursor* = "\e[?25l"
const showCursor* = "\e[?25h"
const bold*       = "\e[1m"

template fg*(color: int): string     = "\e[38;5;" & $color & "m"
template bg*(color: int): string     = "\e[48;5;" & $color & "m"
template cursorUp*(n: int): string   = "\e[" & $n & "A"
template cursorDown*(n: int): string = "\e[" & $n & "B"


type TaskState* = enum
  Pending
  Running
  Done
  Failed


type Ritui* = object
  drawnLines*: int
  previousLines*: int
  tick*: int


const filledColors = [52, 52, 88, 88, 124, 160, 196, 196, 196, 196, 160, 124, 88, 88, 52, 52, 52, 52]
const emptyRunes = ["·", "·", "∴", "∴", "◌", "◌", "✧", "✧", "·", "·", "∵", "∵", "◌", "◌", "✦", "✦", "·", "·"]
const waveLen = 18


proc drawHeader*(ritui: var Ritui, name: string) =
  stdout.write fg(52) & "╭────────────\n"
  stdout.write fg(52) & "│ " & bold & fg(231) & "⛧ " & fg(160) & "Ritual: " & name & "\n"
  stdout.write fg(52) & "├──────────────────\n"
  stdout.write reset & hideCursor
  stdout.flushFile()


proc drawFooter*(ritui: var Ritui) =
  stdout.write fg(52) & "╰────────────────────────" & "\n"
  stdout.write reset & showCursor
  stdout.flushFile()


proc beginFrame*(ritui: var Ritui) =
  if ritui.previousLines > 0:
    stdout.write cursorUp(ritui.previousLines)
  stdout.write "\r"
  ritui.drawnLines = 0


proc endFrame*(ritui: var Ritui) =
  let extra = ritui.previousLines - ritui.drawnLines
  if extra > 0:
    for i in 0 ..< extra:
      stdout.write eraseLine & "\n"
    stdout.write cursorUp(extra)
  ritui.previousLines = ritui.drawnLines
  stdout.flushFile()


proc drawBar*(
  ritui: var Ritui,
  name: string,
  label: string,
  progress: float,
  maxNameLen: int,
  tick: int,
  state: TaskState
) =
  let barWidth = 30
  let filled = clamp(int(progress * float(barWidth)), 0, barWidth)
  let percentage = progress * 100.0
  let paddedName = align(name, maxNameLen)
  let paddedLabel = " " & label
  var bar = reset & "["

  for i in 0 ..< barWidth:
    let idx = (i + tick div 2) mod waveLen
    let hasChar = 0 < i and i < paddedLabel.len

    if i < filled:
      if hasChar:
        bar.add bg(filledColors[idx]) & fg(231) & $paddedLabel[i]
      else:
        bar.add bg(filledColors[idx]) & " "
    else:
      if hasChar:
        bar.add bg(234) & fg(231) & $paddedLabel[i]
      else:
        bar.add fg(236) & emptyRunes[idx]

    bar.add reset

  bar.add "]"

  let begin = "\r" & eraseLine & fg(52) & "│ " & fg(88)
  let suffix = if state == Failed: " " & fg(196) & "ERROR"
               else: " " & fg(88) & $formatFloat(percentage, ffDecimal, 2) & "%"
  stdout.write begin & paddedName & " " & bar & suffix & reset & "\n"
  inc ritui.drawnLines


proc drawState*(tick: int, state: TaskState): string =
  var rune: string
  var color: string
  let idx = (tick div 2) mod waveLen

  case state
  of Done:
    rune = fg(88) & "●" & reset
    color = reset
  of Failed:
    rune = fg(88) & "○" & reset
    color = fg(196)
  else:
    rune = fg(236) & emptyRunes[idx] & reset
    color = reset

  result = rune & " " & color


proc drawLabel*(ritui: var Ritui, name: string, label: string, maxNameLen: int, tick: int, state: TaskState) =
  let paddedName = align(name, maxNameLen)
  let begin = "\r" & eraseLine & fg(52) & "│ " & fg(88)
  let idx = (tick div 2) mod waveLen
  var rune: string
  var color: string

  case state
  of Done:
    rune = fg(88) & "●" & reset
    color = reset
  of Failed:
    rune = fg(88) & "○" & reset
    color = fg(196)
  else:
    rune = fg(236) & emptyRunes[idx] & reset
    color = reset

  stdout.write begin & paddedName & " " & rune & " " & color & label & reset & "\n"
  inc ritui.drawnLines


