import QueuedWorker from "./QueuedWorker"
import * as Msg from "./Msg"
import Repo from "./Repo"
import { whenChanged } from "./Subscription"

type CompileWorker = QueuedWorker<Msg.ToCompiler, Msg.FromCompiler>

export default class Compiler {
  worker: CompileWorker
  repo: Repo
  docUrls: Set<String> = new Set()

  constructor(repo: Repo, url: string) {
    this.repo = repo
    this.worker = new QueuedWorker(url)

    this.worker.subscribe(msg => {
      const handle = this.repo.open(msg.url)

      handle.change((state: any) => {
        switch (msg.t) {
          case "Compiled":
            delete state.error
            delete state.hypermergeFsDiagnostics

            if (getJsSource(state) !== msg.output) {
              state["Source.js"] = msg.output
            }
            break

          case "CompileError":
            state.error = msg.error

            state.hypermergeFsDiagnostics = this.produceDiagnosticsFromMessage(
              msg.error,
            )
            break
        }
      })

      handle.close()
    })
  }

  produceDiagnosticsFromMessage(error: string) {
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
          "in the realm project root.\n\n" +
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

  add(url: string): this {
    if (this.docUrls.has(url)) return this

    this.docUrls.add(url)

    this.repo.open(url).subscribe(
      whenChanged(getElmSource, (source, doc) => {
        console.log("Compiler received updated source file")
        this.worker.send({
          t: "Compile",
          url,
          source,
          debug: doc.debug,
        })
      }),
    )

    return this
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

const getJsSource = (doc: any): string | undefined =>
  doc["Source.js"] || doc["source.js"]
