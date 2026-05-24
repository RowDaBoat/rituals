import workers, ritui


type TuiProc* = proc(ritui: var Ritui, name: string, state: TaskState, maxNameLen: int, tick: int) {.closure.}


type JobKind* = enum
  Sequential
  Parallel
  Run


type Job* {.acyclic.} = ref object
  scriptDir*: string
  case kind*: JobKind
  of Sequential, Parallel:
    children*: seq[Job]
  of Run:
    procedure*: proc()
    renderer*: TuiProc
    state*: TaskState
    startTick*: int
    lastTick*: int
    name*: string
    logPath*: string
    label*: string


proc sequential*(): Job =
  Job(kind: Sequential)


proc parallel*(): Job =
  Job(kind: Parallel)


proc run*(name: string, work: proc()): Job =
  Job(kind: Run, name: name, procedure: work, startTick: -1)


proc wrapWithState*(job: Job): proc() =
  let work = job.procedure
  result = proc() =
    job.state = Running
    try:
      work()
      job.state = Done
    except Exception:
      job.state = Failed
      raise


proc execute*(pool: WorkerPool, job: Job, predecessor: Barrier = nil): Barrier {.discardable.} =
  case job.kind
  of Sequential:
    var prev = predecessor

    for child in job.children:
      prev = pool.execute(child, prev)

    return prev

  of Parallel:
    var barrier = newBarrier()

    for child in job.children:
      pool.send barrier.hold
      let childBarrier = pool.execute(child, predecessor)
      pool.send childBarrier.wait
      pool.send barrier.release
      pool.next()

    return barrier

  of Run:
    let barrier = newBarrier()
    pool.send barrier.hold

    if predecessor != nil:
      pool.send predecessor.wait

    pool.send work(wrapWithState(job))
    pool.send barrier.release
    return barrier
