export interface Compile {
  t: "Compile"
  url: string
  source: string
  sourceHash: string
  outputHash: string | null
  config: { [k: string]: any }
  debug?: boolean
  persist?: boolean
}

export interface Compiled {
  t: "Compiled"
  url: string
  persist?: boolean
  sourceHash: string
  outputHash: string
  output: string
}

export interface CompileError {
  t: "CompileError"
  url: string
  sourceHash: string
  error: string
}

export type ToCompiler = Compile
export type FromCompiler = Compiled | CompileError
