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

def lookup.pick(-A: Data, value: A, fallback: A, found: Bool) -> A:
  match found:
    case True{}:
      value
    case False{}:
      fallback

# ponytail: linear environments suit this tiny profile; use an indexed scope
# representation if large functions make traversal significant.
def lookup(-A: Data, env: List<&2, Binding<A>>, +level: Nat, fallback: A) -> A:
  match env:
    case Nil{}:
      fallback
    case Binding{key, value} <> tail:
      lookup.pick(A, value, lookup(A, tail, level, fallback), Nat.is_eq(key, level))

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

def binary.name(left: Expr, right: Expr, add: Bool, mul: Bool) ->
  Result<&2, &2, String, Expr>:
  match add mul:
    case True{} _:
      Done{Add{left, right}}
    case False{} True{}:
      Done{Mul{left, right}}
    case False{} False{}:
      Fail{"Only direct Base U32.add/U32.mul calls are supported"}

def binary(+name: String, base: Bool, left: Expr, right: Expr) ->
  Result<&2, &2, String, Expr>:
  match base:
    case False{}:
      Fail{"Only direct Base U32.add/U32.mul calls are supported"}
    case True{}:
      binary.name(left, right, String.eq(name, "U32.add"), String.eq(name, "U32.mul"))

# The reader alternates between a term and its binding list. An explicit
# structural fuel derived from the input node count keeps that traversal total
# without unsafe or mutually recursive definitions. It is not a target gas limit.
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
      Fail{"Erased lets are outside this experiment"}
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

def is_u32(term: Core.Term) -> Bool:
  match term:
    case Core.TRef{name, _}:
      String.eq(name, "U32")
    case Core.TADT{name, Nil{}, Nil{}}:
      String.eq(name, "U32")
    case _:
      False{}

def argument(valid: Bool) -> Result<&2, &2, String, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{"This experiment only supports runtime U32 arguments"}

def function.result(body: Core.Term, scope: List<&2, Binding<Bool>>, declarations: List<&2, Core.Declaration>,
  fuel: Nat, valid: Bool) -> Result<&2, &2, String, Function>:
  match valid:
    case False{}:
      Fail{"This experiment only supports a U32 result"}
    case True{}:
      do Result<&2, &2, String, Function>:
        expr : Expr <- read(fuel, Inspect{body, scope}, declarations)
        return Function{Nil{}, expr}

def function.prepend(level: Nat, tail: Function) -> Function:
  match tail:
    case Function{parameters, body}:
      Function{level <> parameters, body}

def function(arity: Nat, typ: Core.Term, body: Core.Term, scope: List<&2, Binding<Bool>>,
  declarations: List<&2, Core.Declaration>, fuel: Nat) -> Result<&2, &2, String, Function>:
  match arity typ body:
    case 0n result expr:
      function.result(expr, scope, declarations, fuel, is_u32(result))
    case 1n+p Core.TAll{Core.Erased{}, _, _, _, _} _:
      Fail{"This experiment only supports runtime U32 arguments"}
    case 1n+p Core.TAll{_, _, _, domain, rest} Core.TLam{_, Core.Bound{+level}, value, _}:
      do Result<&2, &2, String, Function>:
        _ : Unit <- argument(is_u32(Core.bare(domain)))
        tail : Function <- function(p, Core.bare(rest), Core.bare(value), Binding{U32.to_nat(level), True{}} <> scope,
          declarations, fuel)
        return function.prepend(U32.to_nat(level), tail)
    case _ _ _:
      Fail{"This experiment only supports runtime U32 arguments"}

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
