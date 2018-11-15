import Repo from "./Repo"
import Handle from "hypermerge/dist/Handle"
import { applyDiff } from "deep-diff"
import { defaults } from "lodash"
import ElmApp from "./ElmApp"
import { whenChanged } from "./Subscription"
import Compiler from "./Compiler"

export default class WidgetElement extends HTMLElement {
  static set repo(repo: Repo) {
    Widget.repo = repo
  }

  static set compiler(compiler: Compiler) {
    Widget.compiler = compiler
  }

  static get observedAttributes() {
    return ["src", "doc"]
  }

  widget?: Widget
  source?: Handle<any>

  constructor() {
    super()

    this.attachShadow({ mode: "open" })
  }

  get docUrl(): string {
    const url = this.getAttribute("doc")
    if (!url) throw new Error(name + " doc attribute is required!")
    return url
  }

  get src(): string {
    const url = this.getAttribute("src")
    if (!url) throw new Error(name + " src attribute is required!")
    return url
  }

  connectedCallback() {
    this.source = Widget.repo.open(this.src)
    Widget.compiler.add(this.src)

    this.source.subscribe(
      whenChanged(getJsSource, (source, doc) => {
        this.remount(toElm(eval(source)))
      }),
    )
  }

  disconnectedCallback() {
    if (this.source) {
      this.source.close()
      delete this.source
    }
  }

  attributeChangedCallback(name: string, _oldValue: string, _newValue: string) {
    this.disconnectedCallback()
    this.connectedCallback()
  }

  remount(elm: any) {
    this.unmount()
    this.mount(elm)
  }

  mount(elm: any) {
    if (!this.shadowRoot) throw new Error("No shadow root! " + this.src)

    const node = document.createElement("div")
    this.shadowRoot.appendChild(node)

    this.widget = new Widget(node, elm, this.src, this.docUrl)
  }

  unmount() {
    if (this.shadowRoot) {
      this.shadowRoot.innerHTML = ""
    }

    if (this.widget) {
      this.widget.close()
      delete this.widget
    }
  }
}

export class Widget {
  static repo: Repo
  static compiler: Compiler

  handle: Handle<any>
  app: ElmApp

  constructor(node: HTMLElement, elm: any, src: string, docUrl: string) {
    this.handle = Widget.repo.open(docUrl)
    this.app = new ElmApp(elm)

    this.app = new ElmApp(
      elm.init({
        node,
        flags: {
          docUrl,
          src,
        },
      }),
    )

    this.app.subscribe(msg => {
      if (msg.doc) {
        this.handle.change((state: any) => {
          applyDiff(state, msg.doc)
        })
      }

      if (msg.init) {
        this.handle.change((state: any) => {
          defaults(state, msg.init)
        })

        this.handle.subscribe(doc => {
          if (isEmptyDoc(doc)) return
          this.app.send({ doc, msg: null })
        })
      }
    })
  }

  close() {
    this.app.unsubscribe()
    this.handle.close()
  }
}

const getJsSource = (doc: any): string | undefined => doc["source.js"]

function isEmptyDoc(doc: object | null): boolean {
  return !doc || Object.keys(doc).length === 0
}

function toElm(code: string) {
  return Object.values(eval(code))[0]
}
