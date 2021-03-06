import QueuedWorker from "./QueuedWorker"
import FakeWorker from "./FakeWorker"
import * as Msg from "./Msg"
import Repo from "./Repo"
import { whenChanged } from "./Subscription"
import { sha1 } from "./Digest"
import * as Author from "./Author"
import { TextEncoder } from "text-encoding"

type CompileWorker = FakeWorker<Msg.ToCompiler, Msg.FromCompiler>

const PERSIST = "PERSIST" in process.env
const encoder = new TextEncoder()

export default class Compiler {
  static selfDataUrl: string

  static setSelfDataUrl(url: string) {
    Compiler.selfDataUrl = url
  }

  worker: CompileWorker
  repo: Repo
  docUrls: Set<String> = new Set()

  constructor(repo: Repo, url: string) {
    this.repo = repo
    this.worker = new FakeWorker(url)
    //this.worker = new QueuedWorker(url)

    this.worker.subscribe(msg => {
      this.repo.change(msg.url, (state: any) => {
        switch (msg.t) {
          case "Compiled":
            delete state.error
            delete state.hypermergeFsDiagnostics

            if (state.outputHash === msg.outputHash) {
              console.log("Compiled output was identitical. Ignoring.")
              return
            }

            this.log(msg.url, "Compilation successful. Writing to doc.")

            // XXX: Skip setting the lastEditTimestamp if this is the
            // very first compile. We already set it when we bootstrap
            // the code doc. Should probably do something smart with
            // a `timeCreated` and `timeLastModified`.
            if (state.outputHash) {
              state.lastEditTimestamp = Date.now()
            }
            if (Compiler.selfDataUrl) {
              state.authors = Author.recordAuthor(Compiler.selfDataUrl,state.authors)
            }

            state.sourceHash = msg.sourceHash
            state.outputHash = msg.outputHash

            const outputUrl = repo.writeFile(
              encoder.encode(msg.output),
              "text/plain",
            )

            state.outputUrl = outputUrl

            return

          case "CompileError":
            if (state.error === msg.error) {
              console.log("Compile error is already in doc. Ignoring.")
              return
            }
            state.error = msg.error
            state.sourceHash = msg.sourceHash

            this.log(msg.url, "Compile error:", msg.url)

            state.hypermergeFsDiagnostics = produceDiagnosticsFromMessage(
              msg.error,
            )
            return
        }
      })
    })
  }

  add(url: string): this {
    if (this.docUrls.has(url)) return this

    this.docUrls.add(url)

    this.repo.open(url).subscribe(async doc => {
      const source = getElmSource(doc)
      if (!source) return

      const sourceHash = await hashSource(doc)
      const persist = PERSIST && doc.persist

      if (sourceHash === doc.sourceHash) {
        if (persist) {
          this.log(url, "Source is unchanged, but PERSIST is set. Compiling...")
        } else {
          console.log("Source is unchanged, skipping compile.")
          return
        }
      } else {
        this.log(url, "Source has changed. Sending to compiler...")
      }

      this.worker.send({
        t: "Compile",
        url,
        source,
        sourceHash,
        outputHash: doc.outputHash,
        config: doc.config || {},
        debug: doc.debug,
        persist,
      })
    })

    return this
  }

  log(url: string, ...args: string[]): void {
    const tag = url.replace("hypermerge:/", "").slice(0, 5)
    console.log(`[${tag}]`, ...args)
  }

  terminate() {
    this.worker.terminate()
  }
}

function rootError(filename: string, ...messages: string[]) {
  return {
    [filename]: messages.map(message => ({
      severity: "error",
      message,
      startLine: 0,
      startColumn: 0,
      endLine: 0,
      endColumn: 1,
    })),
  }
}

const getElmSource = (doc: any): string | undefined =>
  doc["Source.elm"] || doc["source.elm"]

async function hashSource(doc: any): Promise<string> {
  const extra = JSON.stringify({
    debug: doc.debug,
    config: doc.config,
  })
  return sha1(extra + getElmSource(doc))
}

function produceDiagnosticsFromMessage(error: string) {
  // first line is bogus:
  const jsonString = error.substring(error.indexOf("\n") + 1)
  let json
  try {
    json = JSON.parse(jsonString)
  } catch (e) {
    const snippedError = jsonString.slice(0, 500)
    console.groupCollapsed("Compiler error is not valid JSON")
    console.error(e)
    console.log("Attempting to parse this string:")
    console.log(snippedError)
    console.groupEnd()

    let message = "The compiler threw an error:\n\n" + snippedError

    if (snippedError.includes("elm ENOENT")) {
      message =
        "It looks like your elm npm package broke.\n" +
        "Try running `yarn add elm && yarn remove elm` " +
        "in the farm project root.\n\n" +
        message
    }

    return rootError("Source.elm", message)
  }

  const messageReformat = (message: any[]) =>
    message
      .map(
        (message: any) =>
          typeof message === "string" ? message : "" + message.string + "", // VSCode still needs to add formatting
      )
      .join("")

  if (json.type === "error") {
    return rootError("Source.elm", messageReformat(json.message))
  }

  const nestedProblems = json.errors.map((error: any) =>
    error.problems.map((problem: any) => {
      return {
        severity: "error",
        message: messageReformat(problem.message),
        startLine: problem.region.start.line - 1,
        startColumn: problem.region.start.column - 1,
        endLine: problem.region.end.line - 1,
        endColumn: problem.region.end.column - 1,
      }
    }),
  )

  console.log(nestedProblems)
  return { "Source.elm": [].concat(...nestedProblems) }
}
