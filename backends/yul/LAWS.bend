import ./program.bend as Program
import ../u32.bend as Source
import ./lower.bend as Yul

# The actual lowering, for every IR expression and every input environment.
# The target evaluator models masked U32 operations, not arbitrary Yul/EVM.
law preserves:
  for +expr: Source.Expr
  for +env: List<&2, Source.Binding<U32>>
  {Yul.eval(Yul.lower(expr), env) == Source.eval(expr, env) : U32}

# A readable instance connects the example's arithmetic IR to its Bend source.
def example() -> Source.Expr:
  Source.Let{3n, Source.Mul{Source.Var{0n}, Source.Var{1n}},
    Source.Add{Source.Var{3n}, Source.Var{2n}}}

law example_source:
  for +a: U32
  for +b: U32
  for +c: U32
  {Source.eval(example(), [Source.Binding{0n, a}, Source.Binding{1n, b}, Source.Binding{2n, c}])
    == Program.calculate(a, b, c) : U32}

law example_lowered:
  for +a: U32
  for +b: U32
  for +c: U32
  {Yul.eval(Yul.lower(example()), [Source.Binding{0n, a}, Source.Binding{1n, b}, Source.Binding{2n, c}])
    == Program.calculate(a, b, c) : U32}

law answer:
  {Program.calculate(6, 7, 0) == 42 : U32}

law wrapping:
  {Program.calculate(4294967295, 2, 3) == 1 : U32}
