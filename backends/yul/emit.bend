import Base
import ../../src/core.bend as Core
import ../../src/frontend.bend as Frontend
import ./lower.bend as Yul

def run(file: String, name: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
    program : Core.Program <- Frontend.or_die(Core.Program, result)
    code : String <- Frontend.or_die(String, Yul.compile(program, name))
    IO.write(code)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}:
      run("backends/yul/PROOF.bend", "program.calculate")
    case file <> name <> Nil{}:
      run(file, name)
    case _:
      IO.die(Unit, 1, "Usage: emit.bend [source.bend declaration]")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
