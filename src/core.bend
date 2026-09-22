import Base

# The complete first-order checked syntax. Level(-1) is represented explicitly.
type Level is Data:
  Bound{value: U32}
  Placeholder{}

type Quantity is Data:
  Erased{}
  Affine{}
  Reusable{}

type Pattern is Data:
  PVar{name: String, level: Level, quantity: Quantity}
  PCtr{name: String, children: List<&2, Pattern>}

type Literal is Data:
  Natural{decimal: String}
  Text{value: String}

type Binder<-A: Data> is Data:
  Binder{name: String, level: Level, quantity: Quantity, value: A}

type Term is Data:
  TVar{name: String, level: Level, memo: Maybe<&2, Term>}
  TRef{name: String, parallel: Maybe<&2, Bool>}
  TSub{level: Level, value: Either<&2, &2, Term, Pattern>, body: Term}
  TLet{bindings: List<&2, Binder<Term>>, body: Term}
  TTyp{kind: Term}
  TQnt{}
  TQua{quantity: Quantity}
  TMin{left: Term, right: Term}
  TAll{quantity: Quantity, name: String, level: Level, domain: Term, body: Term}
  TLam{name: String, level: Level, body: Term, quantity: Maybe<&2, Quantity>}
  TApp{func: Term, arg: Term}
  TADT{name: String, args: List<&2, Term>, excluded: List<&2, String>}
  TCtr{name: String, args: List<&2, Term>}
  TLit{value: Literal}
  TMat{name: String, hit: Term, miss: Term}
  TEfq{}
  TEql{left: Term, right: Term, typ: Term}
  TRfl{}
  TRwt{equality: Term, motive: Term, body: Term}
  THol{name: String}
  TAnn{value: Term, typ: Term}

type Header is Data:
  Header{name: String, base: Bool, arity: U32, typ: Term}

type Constructor is Data:
  Constructor{name: String, arity: U32, typ: Term}

type Declaration is Data:
  Algebraic{header: Header, parameters: U32, quantity_parameters: U32,
    constructors: List<&2, Constructor>}
  Definition{header: Header, template_parameters: U32, unsafe: Bool,
    foreign: List<&2, String>, source: Maybe<&2, Term>, checked: Maybe<&2, Term>}

type Instance is Data:
  Instance{key: String, name: String}

type Template is Data:
  Template{name: String, instances: List<&2, Instance>}

type Program is Data:
  Program{format: String, version: U32, repository: String, commit: String,
    entry: String, inputs: List<&2, String>, order: List<&2, String>,
    templates: List<&2, Template>, declarations: List<&2, Declaration>, nodes: U32}

# Transparent checker annotations do not introduce runtime bindings.
def bare(term: Term) -> Term:
  match term:
    case TAnn{value, typ}:
      bare(value)
    case TVar{name, level, Some{value}}:
      bare(value)
    case other:
      other

def header(declaration: Declaration) -> Header:
  match declaration:
    case Algebraic{info, _, _, _}:
      info
    case Definition{info, _, _, _, _, _}:
      info

def name(info: Header) -> String:
  match info:
    case Header{value, _, _, _}:
      value

def base(info: Header) -> Bool:
  match info:
    case Header{_, value, _, _}:
      value

def select(found: Bool, value: Declaration, rest: Maybe<&2, Declaration>) -> Maybe<&2, Declaration>:
  match found:
    case True{}:
      Some{value}
    case False{}:
      rest

# ponytail: linear lookup is enough for the examples; index declarations if
# profiling shows repeated lookup matters for larger consumers.
def find(declarations: List<&2, Declaration>, +wanted: String) -> Maybe<&2, Declaration>:
  match declarations:
    case Nil{}:
      None{}
    case +value <> rest:
      select(String.eq(name(header(value)), wanted), value, find(rest, wanted))

def is_base(found: Maybe<&2, Declaration>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{value}:
      base(header(value))
