import Base
import ./core.bend as Core
import ./wire.bend as Wire
import ./decode.bend as Decode

# The host returns generic data; Bend decodes and validates it.
def load(file: String) -> IO(Result<&2, &2, String, Wire.Value<Unit>>):
  import "../host/effects.js"

def write(file: String, program: Core.Program) -> IO(Result<&2, &2, String, Unit>):
  import "../host/effects.js"

def accept(program: Core.Program, missing: Bool, closed: Bool, holes: U32, open: U32) ->
  Result<&2, &2, String, Core.Program>:
  match missing closed:
    case True{} _:
      Fail{"PROOF.bend must import the adjacent LAWS.bend"}
    case False{} False{}:
      Fail{"Incomplete program: " ++ U32.show(holes) ++ " proof holes and " ++ U32.show(open) ++ " open laws"}
    case False{} True{}:
      Done{program}

def decoded(loaded: Decode.Loaded) -> Result<&2, &2, String, Core.Program>:
  match loaded:
    case Decode.Loaded{program, +holes, +open, missing}:
      accept(program, missing, U32.is_zero(holes) && U32.is_zero(open), holes, open)

def finish(loaded: Result<&2, &2, String, Wire.Value<Unit>>) -> Result<&2, &2, String, Core.Program>:
  do Result<&2, &2, String, Core.Program>:
    value : Wire.Value<Unit> <- loaded
    parsed : Decode.Loaded <- Decode.read(value)
    decoded(parsed)

def check(file: String) -> IO(Result<&2, &2, String, Core.Program>):
  do IO<Result<&2, &2, String, Core.Program>>:
    loaded : Result<&2, &2, String, Wire.Value<Unit>> <- load(file)
    return finish(loaded)

def unsafe_names(declarations: List<&2, Core.Declaration>) -> List<&2, String>:
  match declarations:
    case Nil{}:
      Nil{}
    case Core.Definition{info, _, True{}, _, _, _} <> tail:
      Core.name(info) <> unsafe_names(tail)
    case _ <> tail:
      unsafe_names(tail)

def foreign_names(declarations: List<&2, Core.Declaration>) -> List<&2, String>:
  match declarations:
    case Nil{}:
      Nil{}
    case Core.Definition{info, _, _, _ <> _, _, _} <> tail:
      Core.name(info) <> foreign_names(tail)
    case _ <> tail:
      foreign_names(tail)

def summary(program: Core.Program) -> String:
  match program:
    case Core.Program{_, _, _, commit, entry, _, _, _, +declarations, _}:
      "file: " ++ entry ++ "\nupstream: " ++ commit
        ++ "\ndeclarations: " ++ Nat.show(List.length(&2, Core.Declaration, declarations))
        ++ "\nunsafeDeclarations: " ++ String.join(unsafe_names(declarations), ", ")
        ++ "\nforeignDeclarations: " ++ String.join(foreign_names(declarations), ", ")
