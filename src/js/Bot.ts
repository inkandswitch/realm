import Repo from "./Repo"
import { Handle } from "hypermerge/dist/Handle"
import { whenChanged } from "./Subscription"
import Compiler from "./Compiler"
import ElmGizmo from "./ElmGizmo"
import * as Code from "./Code"

export default class Bot {
  static set repo(repo: Repo) {
    ElmGizmo.repo = repo
  }

  static set compiler(compiler: Compiler) {
    ElmGizmo.compiler = compiler
  }

  static set selfDataUrl(selfDataUrl: string) {
    ElmGizmo.selfDataUrl = selfDataUrl
  }

  gizmo?: ElmGizmo
  source?: Handle<any>
  codeUrl: string
  dataUrl: string
  repo = ElmGizmo.repo

  constructor(codeUrl: string, dataUrl: string) {
    this.codeUrl = codeUrl
    this.dataUrl = dataUrl
  }

  start() {
    this.source = this.repo.open(this.codeUrl)
    ElmGizmo.compiler.add(this.codeUrl)

    this.source.subscribe(
      whenChanged(
        doc => doc.outputHash,
        async (outputHash, doc) => {
          const source = await Code.source(this.repo, doc)
          this.remount(toElm(eval(source)), doc)
        },
      ),
    )
  }

  stop() {
    if (this.source) {
      this.source.close()
      delete this.source
    }
  }

  remount(elm: any, codeDoc: any) {
    this.unmount()
    this.mount(elm, codeDoc)
  }

  mount(elm: any, codeDoc: any) {
    this.repo.once(this.dataUrl, (doc: any) => {
      this.gizmo = new ElmGizmo(null, elm, {
        code: this.codeUrl,
        data: this.dataUrl,
        config: codeDoc.config,
        doc,
        all: {
          code: this.codeUrl,
          data: this.dataUrl,
        },
      })
    })
  }

  unmount() {
    if (this.gizmo) {
      this.gizmo.close()
      delete this.gizmo
    }
  }
}

function toElm(code: string) {
  return Object.values(eval(code))[0]
}
