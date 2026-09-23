import ./LAWS.bend as Laws
import ../u32.bend as Source
import ./lower.bend as Yul

def Laws.preserves(expr, env):
  match expr:
    case Source.Var{level}:
      {==}
    case Source.Add{left, right}:
      %Laws.preserves(left, env) :
        {Yul.eval(Yul.lower(Source.Add{left, right}), env) == U32.add(_, Source.eval(right, env)) : U32}
      %Laws.preserves(right, env) :
        {Yul.eval(Yul.lower(Source.Add{left, right}), env) == U32.add(Yul.eval(Yul.lower(left), env), _) : U32}
      {==}
    case Source.Mul{left, right}:
      %Laws.preserves(left, env) :
        {Yul.eval(Yul.lower(Source.Mul{left, right}), env) == U32.mul(_, Source.eval(right, env)) : U32}
      %Laws.preserves(right, env) :
        {Yul.eval(Yul.lower(Source.Mul{left, right}), env) == U32.mul(Yul.eval(Yul.lower(left), env), _) : U32}
      {==}
    case Source.Let{level, value, body}:
      %Laws.preserves(value, env) :
        {Yul.eval(Yul.lower(Source.Let{level, value, body}), env)
          == Source.eval(body, Source.Binding{level, _} <> env) : U32}
      Laws.preserves(body, Source.Binding{level, Yul.eval(Yul.lower(value), env)} <> env)

def Laws.example_source(a, b, c):
  {==}

def Laws.example_lowered(a, b, c):
  %Laws.example_source(a, b, c) :
    {Yul.eval(Yul.lower(Laws.example()), [Source.Binding{0n, a}, Source.Binding{1n, b}, Source.Binding{2n, c}])
      == _ : U32}
  Laws.preserves(Laws.example(), [Source.Binding{0n, a}, Source.Binding{1n, b}, Source.Binding{2n, c}])

def Laws.answer():
  {==}

def Laws.wrapping():
  {==}
