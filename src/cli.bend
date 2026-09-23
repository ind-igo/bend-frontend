import Base
import ./core.bend as Core
import ./frontend.bend as Frontend

def usage() -> String:
  "bend-frontend\n\n  check <file.bend>\n  export <file.bend> -o <output.json>\n  --help\n"

def check_file(file: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
    program : Core.Program <- Frontend.or_die(Core.Program, result)
    IO.print(Frontend.summary(program))

def export_file(file: String, +output: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Core.Program> <- Frontend.check(file)
    program : Core.Program <- Frontend.or_die(Core.Program, result)
    written : Result<&2, &2, String, Unit> <- Frontend.write(output, program)
    Frontend.or_die(Unit, written)
    IO.print("output: " ++ output)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.print(usage())
    case "--help" <> Nil{}:
      IO.print(usage())
    case "-h" <> Nil{}:
      IO.print(usage())
    case "check" <> file <> Nil{}:
      check_file(file)
    case "export" <> file <> "-o" <> output <> Nil{}:
      export_file(file, output)
    case "export" <> file <> "--output" <> output <> Nil{}:
      export_file(file, output)
    case _:
      IO.die(Unit, 1, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
