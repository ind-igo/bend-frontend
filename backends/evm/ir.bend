import Base
import ./Evm.bend as Evm

# The contract IR. Each constructor is one DSL call, so run(cmd) normalizes to
# the same term as the source contract; certificates check that with {==}.
type Expr is Data:
  Lit{value: Nat}
  Var{level: Nat}

type Cond is Data:
  Eq{left: Expr, right: Expr}
  Lt{left: Expr, right: Expr}

# Word actions return a word; effects return Unit.
type Word is Data:
  SLoad{key: Expr}
  Caller{}
  Add{left: Expr, right: Expr}

type Effect is Data:
  SStore{key: Expr, value: Expr}
  Require{cond: Cond}

type Cmd is Data:
  Bind{word: Word, level: Nat, body: Cmd}
  Then{effect: Effect, body: Cmd}
  Return{value: Expr}
  Tail{word: Word}
  Finish{effect: Effect}
  Stop{}

# What an entry point returns.
type Output is Data:
  Returns{}
  Stops{}

def value(out: Output) -> Data:
  match out:
    case Returns{}:
      Nat
    case Stops{}:
      Unit

type Binding is Data:
  Binding{level: Nat, value: Nat}

def lookup(env: List<&2, Binding>, +level: Nat) -> Nat:
  match env:
    case Nil{}:
      0n
    case Binding{k, v} <> rest:
      Bool.pick(Nat, Nat.is_eq(k, level), v, lookup(rest, level))

def eval(expr: Expr, +env: List<&2, Binding>) -> Nat:
  match expr:
    case Lit{value}:
      value
    case Var{level}:
      lookup(env, level)

def cond(c: Cond, +env: List<&2, Binding>) -> Bool:
  match c:
    case Eq{left, right}:
      Nat.is_eq(eval(left, env), eval(right, env))
    case Lt{left, right}:
      Nat.is_lt(eval(left, env), eval(right, env))

def word(w: Word, +env: List<&2, Binding>) -> Evm.Contract(Nat):
  match w:
    case SLoad{key}:
      Evm.sload(eval(key, env))
    case Caller{}:
      Evm.caller()
    case Add{left, right}:
      Evm.add(eval(left, env), eval(right, env))

def effect(e: Effect, +env: List<&2, Binding>) -> Evm.Contract(Unit):
  match e:
    case SStore{key, value}:
      Evm.sstore(eval(key, env), eval(value, env))
    case Require{c}:
      Evm.require(cond(c, env))

def abort(-A: Data) -> Evm.Contract(A):
  s => Evm.Revert{}

# A tail whose kind differs from the entry's output is ill-formed and reverts.
def run(cmd: Cmd, +out: Output, +env: List<&2, Binding>) -> Evm.Contract(value(out)):
  match cmd out:
    case Bind{w, level, body} o:
      Evm.Contract.bind(Nat, value(o), word(w, env), x => run(body, o, Binding{level, x} <> env))
    case Then{e, body} o:
      Evm.Contract.bind(Unit, value(o), effect(e, env), _ => run(body, o, env))
    case Return{v} Returns{}:
      Evm.Contract.pure(Nat, eval(v, env))
    case Tail{w} Returns{}:
      word(w, env)
    case Finish{e} Stops{}:
      effect(e, env)
    case Stop{} Stops{}:
      Evm.Contract.pure(Unit, Unit{})
    case _ o:
      abort(value(o))

# Scope checks: an unbound Var would read as 0 in lookup and could hide a
# wrong IR behind a literal 0 in the source.
def has(levels: List<&2, Nat>, +level: Nat) -> Bool:
  match levels:
    case Nil{}:
      False{}
    case k <> rest:
      Bool.or(Nat.is_eq(k, level), has(rest, level))

def closed.expr(e: Expr, +scope: List<&2, Nat>) -> Bool:
  match e:
    case Lit{_}:
      True{}
    case Var{level}:
      has(scope, level)

def closed.two(left: Expr, right: Expr, +scope: List<&2, Nat>) -> Bool:
  Bool.and(closed.expr(left, scope), closed.expr(right, scope))

def closed.word(w: Word, +scope: List<&2, Nat>) -> Bool:
  match w:
    case SLoad{key}:
      closed.expr(key, scope)
    case Caller{}:
      True{}
    case Add{left, right}:
      closed.two(left, right, scope)

def closed.effect(e: Effect, +scope: List<&2, Nat>) -> Bool:
  match e:
    case SStore{key, value}:
      closed.two(key, value, scope)
    case Require{Eq{left, right}}:
      closed.two(left, right, scope)
    case Require{Lt{left, right}}:
      closed.two(left, right, scope)

def closed(cmd: Cmd, +scope: List<&2, Nat>) -> Bool:
  match cmd:
    case Bind{w, level, body}:
      Bool.and(closed.word(w, scope), closed(body, level <> scope))
    case Then{e, body}:
      Bool.and(closed.effect(e, scope), closed(body, scope))
    case Return{v}:
      closed.expr(v, scope)
    case Tail{w}:
      closed.word(w, scope)
    case Finish{e}:
      closed.effect(e, scope)
    case Stop{}:
      True{}

def levels(env: List<&2, Binding>) -> List<&2, Nat>:
  match env:
    case Nil{}:
      Nil{}
    case Binding{level, _} <> rest:
      level <> levels(rest)

# An entry point: reverts unless every variable is bound, then runs.
def call(+cmd: Cmd, +out: Output, +env: List<&2, Binding>) -> Evm.Contract(value(out)):
  Bool.pick(Evm.Contract(value(out)), closed(cmd, levels(env)), run(cmd, out, env), abort(value(out)))
