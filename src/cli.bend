import Base
import ./core.bend as Core
import ./frontend.bend as Frontend

def usage() -> String:
  "bend-frontend\n\n  check <file.bend>\n  export <file.bend> -o <output.json>\n  --help\n"

def printed(result: Result<&2, &2, String, Core.Program>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{program}:
      IO.print(Frontend.summary(program))

def written(output: String, result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{value}:
      IO.print("output: " ++ output)

def exported(+output: String, result: Result<&2, &2, String, Core.Program>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{program}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Frontend.write(output, program)
        written(output, result)

def checking(file: String, valid: Bool) -> IO(Unit):
  match valid:
    case False{}:
      IO.die(Unit, 1, usage())
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
        printed(result)

def exporting(file: String, output: String, valid: Bool) -> IO(Unit):
  match valid:
    case False{}:
      IO.die(Unit, 1, usage())
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
        exported(output, result)

def help(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print(usage())
    case False{}:
      IO.die(Unit, 1, usage())

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.print(usage())
    case +flag <> Nil{}:
      help(String.eq(flag, "--help") || String.eq(flag, "-h"))
    case command <> file <> Nil{}:
      checking(file, String.eq(command, "check"))
    case command <> file <> +flag <> output <> Nil{}:
      exporting(file, output, String.eq(command, "export") &&
        (String.eq(flag, "-o") || String.eq(flag, "--output")))
    case _:
      IO.die(Unit, 1, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
