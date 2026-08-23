import std/[os, terminal, tables, locks]
import ritui, jobs, output, workers, monitor
export ritui, jobs, output


var rituals: Table[string, Job]
var ritualMonitor: ptr Monitor = cast[ptr Monitor](allocShared0(sizeof(Monitor)))
var plaintextMode = false
var cwdLock*: Lock

cwdLock.initLock()


proc sigint() {.noconv.} =
  if not plaintextMode:
    stdout.write reset & showCursor & "\n"
  stdout.flushFile()
  quit(0)


proc listRituals*() =
  for name in rituals.keys:
    echo name


proc resolveReferences(job: Job) =
  case job.kind
  of Sequential, Parallel:
    for i in 0 ..< job.children.len:
      let child = job.children[i]
      if child.kind == Reference:
        if not rituals.hasKey(child.targetName):
          styledEcho fgRed, "Error: ", resetStyle, "Unknown ritual recited: '", child.targetName, "'"
          quit(1)
        let resolved = rituals[child.targetName]
        resolveReferences(resolved)
        job.children[i] = resolved
      else:
        resolveReferences(child)
  of Run, Reference:
    discard


proc runRitual*(name: string, plaintext = false) =
  if not rituals.hasKey(name):
    styledEcho fgRed, "Error: ", resetStyle, "Unknown ritual: '", name, "'"
    quit(1)

  plaintextMode = plaintext or not enableAnsi()
  let job = rituals[name]
  resolveReferences(job)
  let pool = newWorkerPool()
  setCurrentDir(job.scriptDir)
  ritualMonitor[] = startMonitor(name, job, plaintextMode)

  let doneBarrier = newBarrier(1)
  discard pool.execute(job)
  pool.send doneBarrier.release
  doneBarrier.waitSync()

  pool.shutdown()
  ritualMonitor[].stop()
  deallocShared(ritualMonitor)


setControlCHook(sigint)


template ritual*(ritualName: string, body: untyped) =
  block:
    let scriptDir   {.inject, used.} = parentDir(instantiationInfo(-1, true).filename)
    let packageName {.inject, used.} = lastPathPart(scriptDir)
    let callDir     {.inject, used.} = getCurrentDir()
    var jobStack: seq[Job]
    var logCounter = newLogCounter(callDir / defaultLogDir)
    var pendingChild: Job = nil

    proc flushPending(pending: var Job) =
      if pending == nil:
        return

      let child = pending
      pending = nil

      jobStack[^1].children.add child

    template sync() {.used.} =
      flushPending(pendingChild)

    template task(taskName: string, taskBody: untyped) {.used.} =
      task(taskName, "", taskBody)

    template task(taskName: string, taskLabel: string, taskBody: untyped) {.used.} =
      block:
        flushPending(pendingChild)
        let job {.inject, used.} = run(taskName, nil)
        job.scriptDir = scriptDir
        job.logPath = logCounter.nextLogPath(taskName)
        job.label = taskLabel

        job.procedure = proc() =
          {.cast(gcsafe).}:
            cwdLock.acquire()
            setCurrentDir(job.scriptDir)
            cwdLock.release()
          let taskLog {.inject, used.} = newTaskLog(job.logPath)

          template log(message: string) {.used.} =
            taskLog.log(message)

          try:
            taskBody
          except Exception as error:
            job.state = Failed
            {.cast(gcsafe).}:
              ritualMonitor[].fail(job.name, error.msg, job.logPath)
            quit(1)
          finally:
            taskLog.close()

        if taskLabel != "":
          job.renderer = proc(
            ritui: var Ritui,
            name: string,
            state: TaskState,
            maxNameLen: int,
            tick: int
          ) {.closure.} =
            if state == Done:
              ritui.drawLabel(name, bold & job.label, maxNameLen, tick, state)
            else:
              ritui.drawLabel(name, job.label, maxNameLen, tick, state)

        if jobStack.len == 1:
          pendingChild = job
        else:
          jobStack[^1].children.add job

    template tui(tuiBody: untyped) {.used.} =
      let targetJob =
        if pendingChild != nil:
           pendingChild
        else:
          jobStack[^1].children[^1]

      targetJob.renderer = proc(
        ritui: var Ritui,
        name: string,
        state {.inject.}: TaskState,
        maxNameLen: int,
        tick {.inject.}: int
      ) {.closure.} =
        {.cast(gcsafe).}:
          cwdLock.acquire()
        setCurrentDir(targetJob.scriptDir)

        template bar(value: float, barState {.inject.}: TaskState = state) {.used.} =
          ritui.drawBar(name, "", value, maxNameLen, tick, barState)

        template bar(label: string, value: float, barState {.inject.}: TaskState = state) {.used.} =
          ritui.drawBar(name, label, value, maxNameLen, tick, barState)

        template label(text: string, labelState {.inject.}: TaskState = state) {.used.} =
          ritui.drawLabel(name, text, maxNameLen, tick, labelState)

        tuiBody
        {.cast(gcsafe).}:
          cwdLock.release()

    template parallel(parallelBody: untyped) {.used.} =
      flushPending(pendingChild)
      jobStack.add jobs.parallel()
      parallelBody
      let frame = jobStack.pop()

      if jobStack.len == 1:
        pendingChild = frame
      else:
        jobStack[^1].children.add frame

    template sequential(seqBody: untyped) {.used.} =
      flushPending(pendingChild)
      jobStack.add jobs.sequential()
      seqBody
      let frame = jobStack.pop()

      if jobStack.len == 1:
        pendingChild = frame
      else:
        jobStack[^1].children.add frame

    template recite(targetName: string) {.used.} =
      flushPending(pendingChild)

      let resolvedName =
        if '.' in targetName: targetName
        else: packageName & "." & targetName

      let referenceJob = reference(resolvedName)

      if jobStack.len == 1:
        pendingChild = referenceJob
      else:
        jobStack[^1].children.add referenceJob

    jobStack.add jobs.sequential()

    let rootJob = jobStack[0]
    rootJob.scriptDir = scriptDir

    body

    flushPending(pendingChild)
    rituals[packageName & "." & ritualName] = rootJob
