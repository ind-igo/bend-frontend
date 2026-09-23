import Base
import ../../src/core.bend as Core
import ../../src/frontend.bend as Frontend
import ./lower.bend as Yul

def output(result: Result<&2, &2, String, String>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{code}:
      IO.write(code)

def checked(name: String, result: Result<&2, &2, String, Core.Program>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{program}:
      output(Yul.compile(program, name))

def run(file: String, name: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
    checked(name, result)

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
