import Base
import ../../src/core.bend as Core
import ./ir.bend as IR

# The reader proposes IR and the generated certificate proves it. A reader bug
# makes the certificate fail instead of miscompiling, so the reader is untrusted.

# s without the prefix p, if s starts with p.
def after(p: String, s: String) -> Maybe<&2, String>:
  match p s:
    case SNil{} rest:
      Some{rest}
    case SCon{x, xs} SCon{y, ys}:
      Bool.pick(Maybe<&2, String>, Char.is_eq(x, y), after(xs, ys), None{})
    case _ _:
      None{}

def reversed(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{s}:
      Some{String.reverse(s)}
    case None{}:
      None{}

# s without the suffix p, if s ends with p.
def before(p: String, s: String) -> Maybe<&2, String>:
  reversed(after(String.reverse(p), String.reverse(s)))

def canonical(found: Maybe<&2, String>, name: String) -> String:
  match found:
    case Some{rest}:
      "Evm." ++ rest
    case None{}:
      name

# Drop annotations and memos, and rename DSL references to "Evm.*" wherever
# the contract imported the module from. Later patterns can then nest.
def strip(+evm: String, term: Core.Term) -> Core.Term:
  match term:
    case Core.TAnn{value, _}:
      strip(evm, value)
    case Core.TVar{_, _, Some{value}}:
      strip(evm, value)
    case Core.TApp{func, arg}:
      f a = strip(evm, func) strip(evm, arg)
      Core.TApp{f, a}
    case Core.TLam{name, level, body, quantity}:
      Core.TLam{name, level, strip(evm, body), quantity}
    case Core.TRef{+name, parallel}:
      Core.TRef{canonical(after(evm, name), name), parallel}
    case other:
      other

# An application spine: the referenced head and its arguments in order.
# Readers match names on Call, never deep inside Term: nested patterns over
# Term's many constructors make the checker's case trees explode.
type Call is Data:
  Call{name: String, args: List<&2, Core.Term>}
  Other{}

def call(term: Core.Term, args: List<&2, Core.Term>) -> Call:
  match term:
    case Core.TApp{func, arg}:
      call(func, arg <> args)
    case Core.TRef{name, _}:
      Call{name, args}
    case _:
      Other{}

def literal(value: Maybe<&2, Nat>) -> Result<&2, &2, String, IR.Expr>:
  match value:
    case Some{n}:
      Done{IR.Lit{n}}
    case None{}:
      Fail{"Invalid natural literal"}

def natural(value: Core.Literal) -> Result<&2, &2, String, IR.Expr>:
  match value:
    case Core.Natural{decimal}:
      literal(Nat.read(decimal))
    case _:
      Fail{"Only natural literals are words"}

def constant.body(term: Core.Term) -> Result<&2, &2, String, IR.Expr>:
  match term:
    case Core.TLit{value}:
      natural(value)
    case _:
      Fail{"Only literal constants can appear in expressions"}

# A reference to a zero-argument def whose body is a literal is that literal.
def constant(found: Maybe<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Expr>:
  match found:
    case Some{Core.Definition{Core.Header{_, _, 0, _}, 0, False{}, Nil{}, _, Some{body}}}:
      constant.body(Core.bare(body))
    case _:
      Fail{"Only literal constants can appear in expressions"}

def variable(level: Core.Level) -> Result<&2, &2, String, IR.Expr>:
  match level:
    case Core.Bound{value}:
      Done{IR.Var{U32.to_nat(value)}}
    case Core.Placeholder{}:
      Fail{"Unbound variable"}

def expr(term: Core.Term, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Expr>:
  match term:
    case Core.TLit{value}:
      natural(value)
    case Core.TVar{_, level, _}:
      variable(level)
    case Core.TRef{+name, _}:
      constant(Core.find(decls, name))
    case _:
      Fail{"Unsupported expression"}

type Operands is Data:
  Operands{left: IR.Expr, right: IR.Expr}

def operands(left: Core.Term, right: Core.Term, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, Operands>:
  do Result<&2, &2, String, Operands>:
    l : IR.Expr <- expr(left, decls)
    r : IR.Expr <- expr(right, decls)
    return Operands{l, r}

def eq(pair: Operands) -> IR.Cond:
  match pair:
    case Operands{l, r}:
      IR.Eq{l, r}

def lt(pair: Operands) -> IR.Cond:
  match pair:
    case Operands{l, r}:
      IR.Lt{l, r}

def add(pair: Operands) -> IR.Word:
  match pair:
    case Operands{l, r}:
      IR.Add{l, r}

def store(pair: Operands) -> IR.Effect:
  match pair:
    case Operands{k, v}:
      IR.SStore{k, v}

def cond(c: Call, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Cond>:
  match c:
    case Call{"Nat.is_eq", left <> right <> Nil{}}:
      do Result<&2, &2, String, IR.Cond>:
        pair : Operands <- operands(left, right, decls)
        return eq(pair)
    case Call{"Nat.is_lt", left <> right <> Nil{}}:
      do Result<&2, &2, String, IR.Cond>:
        pair : Operands <- operands(left, right, decls)
        return lt(pair)
    case _:
      Fail{"Unsupported condition"}

def word(c: Call, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Word>:
  match c:
    case Call{"Evm.sload", key <> Nil{}}:
      do Result<&2, &2, String, IR.Word>:
        k : IR.Expr <- expr(key, decls)
        return IR.SLoad{k}
    case Call{"Evm.caller", Nil{}}:
      Done{IR.Caller{}}
    case Call{"Evm.add", left <> right <> Nil{}}:
      do Result<&2, &2, String, IR.Word>:
        pair : Operands <- operands(left, right, decls)
        return add(pair)
    case _:
      Fail{"Unsupported word action"}

def effect(c: Call, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Effect>:
  match c:
    case Call{"Evm.sstore", key <> value <> Nil{}}:
      do Result<&2, &2, String, IR.Effect>:
        pair : Operands <- operands(key, value, decls)
        return store(pair)
    case Call{"Evm.require", condition <> Nil{}}:
      do Result<&2, &2, String, IR.Effect>:
        c : IR.Cond <- cond(call(condition, Nil{}), decls)
        return IR.Require{c}
    case _:
      Fail{"Unsupported effect"}

# A bind over a word keeps its value; a bind over Unit is a plain step.
def step(typ: Call, +action: Call, level: Nat, rest: Result<&2, &2, String, IR.Cmd>,
  +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Cmd>:
  match typ:
    case Call{"Nat", Nil{}}:
      do Result<&2, &2, String, IR.Cmd>:
        w : IR.Word <- word(action, decls)
        body : IR.Cmd <- rest
        return IR.Bind{w, level, body}
    case Call{"Unit", Nil{}}:
      do Result<&2, &2, String, IR.Cmd>:
        e : IR.Effect <- effect(action, decls)
        body : IR.Cmd <- rest
        return IR.Then{e, body}
    case _:
      Fail{"Only Nat and Unit results can be bound"}

def bind(c: Call, level: Core.Level, rest: Result<&2, &2, String, IR.Cmd>, +decls: List<&2, Core.Declaration>) ->
  Result<&2, &2, String, IR.Cmd>:
  match c level:
    case Call{"Evm.Contract.bind", typ <> _ <> action <> Nil{}} Core.Bound{value}:
      step(call(typ, Nil{}), call(action, Nil{}), U32.to_nat(value), rest, decls)
    case _ _:
      Fail{"Unsupported binding"}

def unit(term: Core.Term) -> Result<&2, &2, String, IR.Cmd>:
  match term:
    case Core.TCtr{"Unit", Nil{}}:
      Done{IR.Stop{}}
    case _:
      Fail{"Expected Unit{}"}

def pure(typ: Call, value: Core.Term, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Cmd>:
  match typ:
    case Call{"Nat", Nil{}}:
      do Result<&2, &2, String, IR.Cmd>:
        v : IR.Expr <- expr(value, decls)
        return IR.Return{v}
    case Call{"Unit", Nil{}}:
      unit(value)
    case _:
      Fail{"Only Nat and Unit results can be returned"}

def last(w: Result<&2, &2, String, IR.Word>, e: Result<&2, &2, String, IR.Effect>) ->
  Result<&2, &2, String, IR.Cmd>:
  match w e:
    case Done{value} _:
      Done{IR.Tail{value}}
    case _ Done{value}:
      Done{IR.Finish{value}}
    case _ _:
      Fail{"Unsupported contract step"}

def final(c: Call, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Cmd>:
  match c:
    case Call{"Evm.Contract.pure", typ <> value <> Nil{}}:
      pure(call(typ, Nil{}), value, decls)
    case +other:
      last(word(other, decls), effect(other, decls))

def cmd(term: Core.Term, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, IR.Cmd>:
  match term:
    case Core.TApp{func, Core.TLam{_, level, body, _}}:
      bind(call(func, Nil{}), level, cmd(body, decls), decls)
    case other:
      final(call(other, Nil{}), decls)

def output(c: IR.Cmd) -> IR.Output:
  match c:
    case IR.Bind{_, _, body}:
      output(body)
    case IR.Then{_, body}:
      output(body)
    case IR.Return{_}:
      IR.Returns{}
    case IR.Tail{_}:
      IR.Returns{}
    case IR.Finish{_}:
      IR.Stops{}
    case IR.Stop{}:
      IR.Stops{}

type Entry is Data:
  Entry{parameters: List<&2, Nat>, body: IR.Cmd}

def prepend(level: Nat, rest: Entry) -> Entry:
  match rest:
    case Entry{parameters, body}:
      Entry{level <> parameters, body}

# Parameters are the leading lambdas; the certificate checks their types.
def lambdas(arity: Nat, term: Core.Term, +decls: List<&2, Core.Declaration>) -> Result<&2, &2, String, Entry>:
  match arity term:
    case 0n body:
      do Result<&2, &2, String, Entry>:
        c : IR.Cmd <- cmd(body, decls)
        return Entry{Nil{}, c}
    case 1n+p Core.TLam{_, Core.Bound{level}, body, _}:
      do Result<&2, &2, String, Entry>:
        rest : Entry <- lambdas(p, body, decls)
        return prepend(U32.to_nat(level), rest)
    case _ _:
      Fail{"Expected one lambda per parameter"}

def module.found(found: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match found:
    case Some{prefix}:
      Done{prefix}
    case None{}:
      Fail{"Expected an Evm.Contract result"}

def module.call(c: Call) -> Result<&2, &2, String, String>:
  match c:
    case Call{name, _}:
      module.found(before("Contract", name))
    case Other{}:
      Fail{"Expected an Evm.Contract result"}

# The Evm module's name prefix, such as "../Evm.", from the entry's result type.
def module(arity: Nat, typ: Core.Term) -> Result<&2, &2, String, String>:
  match arity typ:
    case n Core.TAnn{value, _}:
      module(n, value)
    case 0n result:
      module.call(call(result, Nil{}))
    case 1n+p Core.TAll{_, _, _, _, body}:
      module(p, body)
    case _ _:
      Fail{"Expected an Evm.Contract result"}

def entry.found(found: Maybe<&2, Core.Declaration>, +evm: String, +decls: List<&2, Core.Declaration>) ->
  Result<&2, &2, String, Entry>:
  match found:
    case Some{Core.Definition{Core.Header{_, _, +arity, _}, 0, False{}, Nil{}, _, Some{body}}}:
      lambdas(U32.to_nat(arity), strip(evm, body), decls)
    case _:
      Fail{"Expected a safe, concrete contract function"}

def entry(+evm: String, +decls: List<&2, Core.Declaration>, name: String) -> Result<&2, &2, String, Entry>:
  entry.found(Core.find(decls, name), evm, decls)

def prefix.found(found: Maybe<&2, Core.Declaration>) -> Result<&2, &2, String, String>:
  match found:
    case Some{Core.Definition{Core.Header{_, _, arity, typ}, _, _, _, _, _}}:
      module(U32.to_nat(arity), typ)
    case _:
      Fail{"Unknown contract function"}

def prefix(+decls: List<&2, Core.Declaration>, name: String) -> Result<&2, &2, String, String>:
  prefix.found(Core.find(decls, name))
