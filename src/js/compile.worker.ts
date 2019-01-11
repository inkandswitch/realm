declare const self: DedicatedWorkerGlobalScope
import { resolve } from "path"

if ((self as any).module) {
  ;(self as any).module.paths.push(resolve("./node_modules"))
}

import QueuedPort from "./QueuedPort"
import { ToCompiler, FromCompiler } from "./Msg"
import fs from "fs"
import elm from "node-elm-compiler"
import AsyncQueue from "./AsyncQueue"
import { lock } from "proper-lockfile"

const port = new QueuedPort<FromCompiler, ToCompiler>(self)
;(self as any).port = port

const workQ = new AsyncQueue<ToCompiler>("compiler:workQ")

workQ.take(work)

port.subscribe(workQ.push)

if (!fs.existsSync(".tmp")) {
  fs.mkdirSync(".tmp")
}

function work(msg: ToCompiler) {
  const { url } = msg
  switch (msg.t) {
    case "Compile":
      const source = msg.source.replace(/^module \w+/, "module Source")

      const sourceFile = "./.tmp/Source.elm"
      const lockOpts = { stale: 5000, retries: 5, realpath: false }

      lock(sourceFile, lockOpts).then(release => {
        fs.writeFile(sourceFile, source, async err => {
          function done() {
            release()
            workQ.take(work)
          }

          if (err) {
            port.send({ t: "CompileError", url, error: err.message })
            return done()
          }

          try {
            const filename = /^main /m.test(source)
              ? "./.tmp/Source.elm" // Compile directly if `main` function exists
              : /^gizmo /m.test(source)
                ? "./src/elm/Harness.elm" // Compile via Harness if `gizmo` function exists
                : "./src/elm/BotHarness.elm" // Otherwise, compile via BotHarness

            const out = await elm.compileToString([filename], {
              output: ".js",
              report: "json",
              debug: msg.debug,
            })

            const output = `
              (new function Wrapper() {
                ${out}
              }).Elm
            `

            port.send({ t: "Compiled", url, output })
            console.log(`Elm compile success: ${url}`)
            return done()
          } catch (e) {
            port.send({ t: "CompileError", url, error: e.message })
            console.log(`Elm compile error: ${url}`)
            return done()
          }
        })
      })
      break
  }
}
