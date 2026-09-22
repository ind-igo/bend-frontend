import ./wire.bend as Wire
import ./core.bend as Core

# Only this module translates upstream field names into the public Core schema.
type Part is Data:
  Term{value: Core.Term, nodes: Nat}
  Pattern{value: Core.Pattern}

def get(value: Wire.Value<Part>, key: String) -> Wire.Value<Part>:
  Wire.get(Part, value, key)

def text(value: Wire.Value<Part>) -> Result<&2, &2, String, String>:
  Wire.text(Part, value)

def number(value: Wire.Value<Part>) -> Result<&2, &2, String, U32>:
  Wire.number(Part, value)

def boolean(value: Wire.Value<Part>) -> Result<&2, &2, String, Bool>:
  Wire.boolean(Part, value)

def flag(value: Wire.Value<Part>) -> Result<&2, &2, String, Bool>:
  match value:
    case Wire.Null{}:
      Done{False{}}
    case other:
      boolean(other)

def strings(value: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, String>>:
  Wire.array(~Part, ~String, ~text, value)

def level(value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Level>:
  match value:
    case Wire.Number{"-1"}:
      Done{Core.Placeholder{}}
    case other:
      do Result<&2, &2, String, Core.Level>:
        value : U32 <- number(other)
        return Core.Bound{value}

def quantity.tag(tag: String) -> Result<&2, &2, String, Core.Quantity>:
  match tag:
    case "None":
      Done{Core.Erased{}}
    case "Lone":
      Done{Core.Affine{}}
    case "Many":
      Done{Core.Reusable{}}
    case other:
      Fail{"Unknown upstream quantity: " ++ other}

def quantity(value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Quantity>:
  do Result<&2, &2, String, Core.Quantity>:
    tag : String <- text(get(value, "$"))
    quantity.tag(tag)

def term(value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Term>:
  match value:
    case Wire.Decoded{Term{value, _}}:
      Done{value}
    case _:
      Fail{"Expected upstream term"}

def pattern(value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Pattern>:
  match value:
    case Wire.Decoded{Pattern{value}}:
      Done{value}
    case _:
      Fail{"Expected upstream pattern"}

def substitution(value: Wire.Value<Part>) -> Result<&2, &2, String, Either<&2, &2, Core.Term, Core.Pattern>>:
  match value:
    case Wire.Decoded{Term{value, _}}:
      Done{Inl{value}}
    case Wire.Decoded{Pattern{value}}:
      Done{Inr{value}}
    case _:
      Fail{"Expected upstream substitution"}

def literal(value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Literal>:
  match value:
    case Wire.Text{value}:
      Done{Core.Text{value}}
    case Wire.Number{value}:
      Done{Core.Natural{value}}
    case _:
      Fail{"Expected upstream literal"}

def bindings(names: Wire.Value<Part>, levels: Wire.Value<Part>, quantities: Wire.Value<Part>, values: Wire.Value<Part>) ->
  Result<&2, &2, String, List<&2, Core.Binder<Core.Term>>>:
  match names levels quantities values:
    case Wire.End{} Wire.End{} Wire.End{} Wire.End{}:
      Done{Nil{}}
    case Wire.Item{k, ks} Wire.Item{i, levels_tail} Wire.Item{q, qs} Wire.Item{v, vs}:
      do Result<&2, &2, String, List<&2, Core.Binder<Core.Term>>>:
        name : String <- text(k)
        lev : Core.Level <- level(i)
        qty : Core.Quantity <- quantity(q)
        value : Core.Term <- term(v)
        tail : List<&2, Core.Binder<Core.Term>> <- bindings(ks, levels_tail, qs, vs)
        return Core.Binder{name, lev, qty, value} <> tail
    case _ _ _ _:
      Fail{"Mismatched upstream let bindings"}

def let_bindings(+value: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, Core.Binder<Core.Term>>>:
  do Result<&2, &2, String, List<&2, Core.Binder<Core.Term>>>:
    names : Wire.Value<Part> <- Wire.items(Part, get(value, "k"))
    levels : Wire.Value<Part> <- Wire.items(Part, get(value, "i"))
    quantities : Wire.Value<Part> <- Wire.items(Part, get(value, "q"))
    values : Wire.Value<Part> <- Wire.items(Part, get(value, "v"))
    bindings(names, levels, quantities, values)

def nodes(value: Wire.Value<Part>) -> Nat:
  match value:
    case Wire.Decoded{Term{_, nodes}}:
      nodes
    case Wire.Array{items}:
      nodes(items)
    case Wire.Object{fields}:
      nodes(fields)
    case Wire.Item{head, tail}:
      (nodes(head) + nodes(tail) : Nat)
    case Wire.Field{_, head, tail}:
      (nodes(head) + nodes(tail) : Nat)
    case _:
      0n

def term.tag(tag: String, +value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Term>:
  match tag:
    case "Var":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        lev : Core.Level <- level(get(value, "i"))
        memo : Maybe<&2, Core.Term> <- Wire.optional(Part, Core.Term, term, get(value, "v"))
        return Core.TVar{name, lev, memo}
    case "Ref":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        parallel : Maybe<&2, Bool> <- Wire.optional(Part, Bool, boolean, get(value, "b"))
        return Core.TRef{name, parallel}
    case "Sub":
      do Result<&2, &2, String, Core.Term>:
        lev : Core.Level <- level(get(value, "i"))
        sub : Either<&2, &2, Core.Term, Core.Pattern> <- substitution(get(value, "v"))
        body : Core.Term <- term(get(value, "f"))
        return Core.TSub{lev, sub, body}
    case "Let":
      do Result<&2, &2, String, Core.Term>:
        binds : List<&2, Core.Binder<Core.Term>> <- let_bindings(value)
        body : Core.Term <- term(get(value, "f"))
        return Core.TLet{binds, body}
    case "Typ":
      do Result<&2, &2, String, Core.Term>:
        kind : Core.Term <- term(get(value, "g"))
        return Core.TTyp{kind}
    case "Qnt":
      Done{Core.TQnt{}}
    case "Qua":
      do Result<&2, &2, String, Core.Term>:
        qty : Core.Quantity <- quantity(get(value, "q"))
        return Core.TQua{qty}
    case "Min":
      do Result<&2, &2, String, Core.Term>:
        left : Core.Term <- term(get(value, "a"))
        right : Core.Term <- term(get(value, "b"))
        return Core.TMin{left, right}
    case "All":
      do Result<&2, &2, String, Core.Term>:
        qty : Core.Quantity <- quantity(get(value, "q"))
        name : String <- text(get(value, "k"))
        lev : Core.Level <- level(get(value, "i"))
        domain : Core.Term <- term(get(value, "A"))
        body : Core.Term <- term(get(value, "B"))
        return Core.TAll{qty, name, lev, domain, body}
    case "Lam":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        lev : Core.Level <- level(get(value, "i"))
        body : Core.Term <- term(get(value, "f"))
        qty : Maybe<&2, Core.Quantity> <- Wire.optional(Part, Core.Quantity, quantity, get(value, "q"))
        return Core.TLam{name, lev, body, qty}
    case "App":
      do Result<&2, &2, String, Core.Term>:
        func : Core.Term <- term(get(value, "f"))
        arg : Core.Term <- term(get(value, "x"))
        return Core.TApp{func, arg}
    case "ADT":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        args : List<&2, Core.Term> <- Wire.array(~Part, ~Core.Term, ~term, get(value, "x"))
        excluded : List<&2, String> <- strings(get(value, "r"))
        return Core.TADT{name, args, excluded}
    case "Ctr":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        args : List<&2, Core.Term> <- Wire.array(~Part, ~Core.Term, ~term, get(value, "x"))
        return Core.TCtr{name, args}
    case "Lit":
      do Result<&2, &2, String, Core.Term>:
        lit : Core.Literal <- literal(get(value, "v"))
        return Core.TLit{lit}
    case "Mat":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        hit : Core.Term <- term(get(value, "h"))
        miss : Core.Term <- term(get(value, "m"))
        return Core.TMat{name, hit, miss}
    case "Efq":
      Done{Core.TEfq{}}
    case "Eql":
      do Result<&2, &2, String, Core.Term>:
        left : Core.Term <- term(get(value, "a"))
        right : Core.Term <- term(get(value, "b"))
        typ : Core.Term <- term(get(value, "T"))
        return Core.TEql{left, right, typ}
    case "Rfl":
      Done{Core.TRfl{}}
    case "Rwt":
      do Result<&2, &2, String, Core.Term>:
        equality : Core.Term <- term(get(value, "e"))
        motive : Core.Term <- term(get(value, "p"))
        body : Core.Term <- term(get(value, "f"))
        return Core.TRwt{equality, motive, body}
    case "Hol":
      do Result<&2, &2, String, Core.Term>:
        name : String <- text(get(value, "k"))
        return Core.THol{name}
    case "Ann":
      do Result<&2, &2, String, Core.Term>:
        body : Core.Term <- term(get(value, "x"))
        typ : Core.Term <- term(get(value, "T"))
        return Core.TAnn{body, typ}
    case other:
      Fail{"Unknown upstream term: " ++ other}

def converted(tag: String, +value: Wire.Value<Part>) -> Result<&2, &2, String, Wire.Value<Part>>:
  do Result<&2, &2, String, Wire.Value<Part>>:
    parsed : Core.Term <- term.tag(tag, value)
    return Wire.Decoded{Term{parsed, (1n + nodes(value) : Nat)}}

# Upstream uses ADT for both a declaration and a term. Declarations have T.
def algebraic(value: Wire.Value<Part>, typ: Wire.Value<Part>) -> Result<&2, &2, String, Wire.Value<Part>>:
  match typ:
    case Wire.Null{}:
      converted("ADT", value)
    case _:
      Done{value}

def object.tag(tag: Wire.Value<Part>, +value: Wire.Value<Part>) -> Result<&2, &2, String, Wire.Value<Part>>:
  match tag:
    case Wire.Null{}:
      Done{value}
    case Wire.Text{"Def"}:
      Done{value}
    case Wire.Text{"ADT"}:
      algebraic(value, get(value, "T"))
    case Wire.Text{"None"}:
      Done{value}
    case Wire.Text{"Lone"}:
      Done{value}
    case Wire.Text{"Many"}:
      Done{value}
    case Wire.Text{"PVar"}:
      do Result<&2, &2, String, Wire.Value<Part>>:
        name : String <- text(get(value, "k"))
        lev : Core.Level <- level(get(value, "i"))
        qty : Core.Quantity <- quantity(get(value, "q"))
        return Wire.Decoded{Pattern{Core.PVar{name, lev, qty}}}
    case Wire.Text{"PCtr"}:
      do Result<&2, &2, String, Wire.Value<Part>>:
        name : String <- text(get(value, "k"))
        children : List<&2, Core.Pattern> <- Wire.array(~Part, ~Core.Pattern, ~pattern, get(value, "x"))
        return Wire.Decoded{Pattern{Core.PCtr{name, children}}}
    case Wire.Text{other}:
      converted(other, value)
    case _:
      Fail{"Invalid upstream tag"}

def object(+value: Wire.Value<Part>) -> Result<&2, &2, String, Wire.Value<Part>>:
  object.tag(get(value, "$"), value)

def constructor(+value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Constructor>:
  do Result<&2, &2, String, Core.Constructor>:
    name : String <- text(get(value, "k"))
    arity : U32 <- number(get(value, "n"))
    typ : Core.Term <- term(get(value, "T"))
    return Core.Constructor{name, arity, typ}

def foreign(value: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, String>>:
  match value:
    case Wire.Null{}:
      Done{Nil{}}
    case value:
      strings(value)

def declaration.tag(tag: String, header: Core.Header, +value: Wire.Value<Part>) ->
  Result<&2, &2, String, Core.Declaration>:
  match tag:
    case "ADT":
      do Result<&2, &2, String, Core.Declaration>:
        parameters : U32 <- number(get(value, "n"))
        quantities : U32 <- number(get(value, "g"))
        constructors : List<&2, Core.Constructor> <- Wire.array(~Part, ~Core.Constructor, ~(x => constructor(x)), get(value, "c"))
        return Core.Algebraic{header, parameters, quantities, constructors}
    case "Def":
      do Result<&2, &2, String, Core.Declaration>:
        parameters : U32 <- number(get(value, "x"))
        unsafe : Bool <- flag(get(value, "u"))
        imports : List<&2, String> <- foreign(get(value, "i"))
        source : Maybe<&2, Core.Term> <- Wire.optional(Part, Core.Term, term, get(value, "v"))
        checked : Maybe<&2, Core.Term> <- Wire.optional(Part, Core.Term, term, get(value, "e"))
        return Core.Definition{header, parameters, unsafe, imports, source, checked}
    case other:
      Fail{"Unknown upstream declaration: " ++ other}

def declaration(name: String, +value: Wire.Value<Part>) -> Result<&2, &2, String, Core.Declaration>:
  do Result<&2, &2, String, Core.Declaration>:
    tag : String <- text(get(value, "$"))
    base : Bool <- flag(get(value, "b"))
    arity : U32 <- number(get(value, "n"))
    typ : Core.Term <- term(get(value, "T"))
    declaration.tag(tag, Core.Header{name, base, arity, typ}, value)

def declarations(fields: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, Core.Declaration>>:
  match fields:
    case Wire.End{}:
      Done{Nil{}}
    case Wire.Field{name, value, tail}:
      do Result<&2, &2, String, List<&2, Core.Declaration>>:
        head : Core.Declaration <- declaration(name, value)
        tail : List<&2, Core.Declaration> <- declarations(tail)
        return head <> tail
    case _:
      Fail{"Malformed upstream declarations"}

def instances(fields: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, Core.Instance>>:
  match fields:
    case Wire.End{}:
      Done{Nil{}}
    case Wire.Field{key, value, tail}:
      do Result<&2, &2, String, List<&2, Core.Instance>>:
        name : String <- text(value)
        tail : List<&2, Core.Instance> <- instances(tail)
        return Core.Instance{key, name} <> tail
    case _:
      Fail{"Malformed upstream template instances"}

def templates(fields: Wire.Value<Part>) -> Result<&2, &2, String, List<&2, Core.Template>>:
  match fields:
    case Wire.End{}:
      Done{Nil{}}
    case Wire.Field{name, value, tail}:
      do Result<&2, &2, String, List<&2, Core.Template>>:
        fields : Wire.Value<Part> <- Wire.fields(Part, value)
        head : List<&2, Core.Instance> <- instances(fields)
        tail : List<&2, Core.Template> <- templates(tail)
        return Core.Template{name, head} <> tail
    case _:
      Fail{"Malformed upstream templates"}

type Loaded is Data:
  Loaded{program: Core.Program, holes: U32, open: U32, paired_laws_missing: Bool}

def program(+value: Wire.Value<Part>) -> Result<&2, &2, String, Loaded>:
  do Result<&2, &2, String, Loaded>:
    repository : String <- text(get(value, "repository"))
    commit : String <- text(get(value, "commit"))
    entry : String <- text(get(value, "entry"))
    inputs : List<&2, String> <- strings(get(value, "inputs"))
    order : List<&2, String> <- strings(get(value, "order"))
    tmps : Wire.Value<Part> <- Wire.fields(Part, get(value, "templates"))
    tmps : List<&2, Core.Template> <- templates(tmps)
    defs : Wire.Value<Part> <- Wire.fields(Part, get(value, "declarations"))
    defs : List<&2, Core.Declaration> <- declarations(defs)
    count : U32 <- number(Wire.Number{Nat.show(nodes(value))})
    holes : U32 <- number(get(value, "holes"))
    open : U32 <- number(get(value, "open"))
    missing : Bool <- boolean(get(value, "paired_laws_missing"))
    return Loaded{Core.Program{"bend-frontend.core", 2, repository, commit, entry,
      inputs, order, tmps, defs, count}, holes, open, missing}

def read(value: Wire.Value<Unit>) -> Result<&2, &2, String, Loaded>:
  do Result<&2, &2, String, Loaded>:
    value : Wire.Value<Part> <- Wire.fold(~Part, ~(x => object(x)), value)
    program(value)
