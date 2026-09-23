import Base
import ../src/core.bend as Core

# A deliberately small, target-independent arithmetic IR.
type Expr is Data:
  Var{level: Nat}
  Add{left: Expr, right: Expr}
  Mul{left: Expr, right: Expr}
  Let{level: Nat, value: Expr, body: Expr}

type Binding<-A: Data> is Data:
  Binding{level: Nat, value: A}

type Function is Data:
  Function{parameters: List<&2, Nat>, body: Expr}

# ponytail: linear environments suit this tiny profile; use an indexed scope
# representation if large functions make traversal significant.
def lookup(-A: Data, env: List<&2, Binding<A>>, +level: Nat, fallback: A) -> A:
  match env:
    case Nil{}:
      fallback
    case Binding{key, value} <> tail:
      Bool.pick(A, Nat.is_eq(key, level), value, lookup(A, tail, level, fallback))

def eval(expr: Expr, +env: List<&2, Binding<U32>>) -> U32:
  match expr:
    case Var{level}:
      lookup(U32, env, level, 0)
    case Add{left, right}:
      a b = eval(left, env) eval(right, env)
      U32.add(a, b)
    case Mul{left, right}:
      a b = eval(left, env) eval(right, env)
      U32.mul(a, b)
    case Let{level, value, body}:
      eval(body, Binding{level, eval(value, env)} <> env)

def variable(level: Nat, present: Bool) -> Result<&2, &2, String, Expr>:
  match present:
    case True{}:
      Done{Var{level}}
    case False{}:
      Fail{"Unbound variable"}

def binary(name: String, base: Bool, left: Expr, right: Expr) -> Result<&2, &2, String, Expr>:
  match name base:
    case "U32.add" True{}:
      Done{Add{left, right}}
    case "U32.mul" True{}:
      Done{Mul{left, right}}
    case _ _:
      Fail{"Only direct Base U32.add/U32.mul calls are supported"}

# The reader alternates between a term and its binding list. An explicit
# structural fuel derived from the input node count keeps that traversal total
# without unsafe or mutually recursive definitions. It is not a target gas limit.
# Fuel bounds depth, not work: a term costs two steps (Inspect, then its task)
# and a binder one more, so 3 * nodes + 1 suffices. See entry.found.
type Task is Data:
  Inspect{term: Core.Term, scope: List<&2, Binding<Bool>>}
  Variable{level: Nat, scope: List<&2, Binding<Bool>>}
  Binary{op: String, left: Core.Term, right: Core.Term, scope: List<&2, Binding<Bool>>}
  Group{bindings: List<&2, Core.Binder<Core.Term>>, body: Core.Term, scope: List<&2, Binding<Bool>>}
  Invalid{}

def application.head(head: Core.Term, left: Core.Term, right: Core.Term, scope: List<&2, Binding<Bool>>) -> Task:
  match head:
    case Core.TRef{name, _}:
      Binary{name, left, right, scope}
    case _:
      Invalid{}

def application(func: Core.Term, right: Core.Term, scope: List<&2, Binding<Bool>>) -> Task:
  match func:
    case Core.TApp{head, left}:
      application.head(Core.bare(head), left, right, scope)
    case _:
      Invalid{}

def classify(term: Core.Term, scope: List<&2, Binding<Bool>>) -> Task:
  match term:
    case Core.TVar{_, Core.Bound{level}, None{}}:
      Variable{U32.to_nat(level), scope}
    case Core.TApp{func, arg}:
      application(Core.bare(func), arg, scope)
    case Core.TLet{bindings, body}:
      Group{bindings, body, scope}
    case _:
      Invalid{}

def runtime(quantity: Core.Quantity) -> Result<&2, &2, String, Unit>:
  match quantity:
    case Core.Erased{}:
      Fail{"Erased lets are not supported"}
    case _:
      Done{Unit{}}

def read(+fuel: Nat, task: Task, +declarations: List<&2, Core.Declaration>) -> Result<&2, &2, String, Expr>:
  match fuel task:
    case 0n _:
      Fail{"Core traversal budget exhausted"}
    case 1n+p Inspect{term, scope}:
      read(p, classify(Core.bare(term), scope), declarations)
    case 1n+p Variable{+level, scope}:
      variable(level, lookup(Bool, scope, level, False{}))
    case 1n+p Binary{+name, left, right, +scope}:
      do Result<&2, &2, String, Expr>:
        a : Expr <- read(p, Inspect{left, scope}, declarations)
        b : Expr <- read(p, Inspect{right, scope}, declarations)
        binary(name, Core.is_base(Core.find(declarations, name)), a, b)
    case 1n+p Group{Nil{}, body, scope}:
      read(p, Inspect{body, scope}, declarations)
    case 1n+p Group{Core.Binder{_, Core.Bound{+level}, quantity, value} <> tail, body, +scope}:
      do Result<&2, &2, String, Expr>:
        _ : Unit <- runtime(quantity)
        a : Expr <- read(p, Inspect{value, scope}, declarations)
        b : Expr <- read(p, Group{tail, body, Binding{U32.to_nat(level), True{}} <> scope}, declarations)
        return Let{U32.to_nat(level), a, b}
    case _ _:
      Fail{"Unsupported runtime term"}

def argument_error() -> String:
  "Only runtime U32 arguments are supported"

# Base U32 appears as a reference or as an ADT without arguments.
def u32(term: Core.Term, error: String) -> Result<&2, &2, String, Unit>:
  match term:
    case Core.TRef{"U32", _}:
      Done{Unit{}}
    case Core.TADT{"U32", Nil{}, Nil{}}:
      Done{Unit{}}
    case _:
      Fail{error}

def function.prepend(level: Nat, tail: Function) -> Function:
  match tail:
    case Function{parameters, body}:
      Function{level <> parameters, body}

def function(arity: Nat, typ: Core.Term, body: Core.Term, scope: List<&2, Binding<Bool>>,
  declarations: List<&2, Core.Declaration>, fuel: Nat) -> Result<&2, &2, String, Function>:
  match arity typ body:
    case 0n result value:
      do Result<&2, &2, String, Function>:
        _ : Unit <- u32(result, "Only a U32 result is supported")
        lowered : Expr <- read(fuel, Inspect{value, scope}, declarations)
        return Function{Nil{}, lowered}
    case 1n+p Core.TAll{Core.Erased{}, _, _, _, _} _:
      Fail{argument_error()}
    case 1n+p Core.TAll{_, _, _, domain, rest} Core.TLam{_, Core.Bound{+level}, value, _}:
      do Result<&2, &2, String, Function>:
        _ : Unit <- u32(Core.bare(domain), argument_error())
        tail : Function <- function(p, Core.bare(rest), Core.bare(value), Binding{U32.to_nat(level), True{}} <> scope,
          declarations, fuel)
        return function.prepend(U32.to_nat(level), tail)
    case _ _ _:
      Fail{argument_error()}

def entry.found(found: Maybe<&2, Core.Declaration>, declarations: List<&2, Core.Declaration>, nodes: U32) ->
  Result<&2, &2, String, Function>:
  match found:
    case Some{Core.Definition{Core.Header{_, _, arity, typ}, 0, False{}, Nil{}, _, Some{body}}}:
      function(U32.to_nat(arity), Core.bare(typ), Core.bare(body), Nil{}, declarations, (4n * U32.to_nat(nodes) + 8n : Nat))
    case _:
      Fail{"Expected a safe, concrete function"}

def entry.base(+declarations: List<&2, Core.Declaration>, name: String, nodes: U32, valid: Bool) ->
  Result<&2, &2, String, Function>:
  match valid:
    case False{}:
      Fail{"Expected upstream Base.U32"}
    case True{}:
      entry.found(Core.find(declarations, name), declarations, nodes)

def entry(program: Core.Program, name: String) -> Result<&2, &2, String, Function>:
  match program:
    case Core.Program{_, _, _, _, _, _, _, _, +declarations, nodes}:
      entry.base(declarations, name, nodes, Core.is_base(Core.find(declarations, "U32")))
