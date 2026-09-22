import Base

# Generic host transport. This knows nothing about upstream terms or Core.
# ponytail: a boxed tree keeps the bridge small; stream declarations if large
# whole-book exports make transport allocations prohibitive.
type Value<-A: Data> is Data:
  Null{}
  Boolean{value: Bool}
  Number{decimal: String}
  Text{value: String}
  Array{items: Value<A>}
  Object{fields: Value<A>}
  End{}
  Item{value: Value<A>, rest: Value<A>}
  Field{name: String, value: Value<A>, rest: Value<A>}
  Decoded{value: A}

def pick(-A: Data, found: Bool, value: Value<A>, rest: Value<A>) -> Value<A>:
  match found:
    case True{}:
      value
    case False{}:
      rest

def field(-A: Data, fields: Value<A>, +key: String) -> Value<A>:
  match fields:
    case Field{name, value, rest}:
      pick(A, String.eq(name, key), value, field(A, rest, key))
    case _:
      Null{}

def get(-A: Data, value: Value<A>, key: String) -> Value<A>:
  match value:
    case Object{fields}:
      field(A, fields, key)
    case _:
      Null{}

def text(-A: Data, value: Value<A>) -> Result<&2, &2, String, String>:
  match value:
    case Text{value}:
      Done{value}
    case _:
      Fail{"Expected text in upstream data"}

def boolean(-A: Data, value: Value<A>) -> Result<&2, &2, String, Bool>:
  match value:
    case Boolean{value}:
      Done{value}
    case _:
      Fail{"Expected boolean in upstream data"}

def number.fit(value: U32, fits: Bool) -> Result<&2, &2, String, U32>:
  match fits:
    case True{}:
      Done{value}
    case False{}:
      Fail{"Core metadata exceeds U32 range"}

def number.read(value: Maybe<&2, U32>, decimal: String) -> Result<&2, &2, String, U32>:
  match value:
    case Some{+value}:
      number.fit(value, String.eq(U32.show(value), decimal))
    case None{}:
      Fail{"Core metadata exceeds U32 range"}

def number(-A: Data, value: Value<A>) -> Result<&2, &2, String, U32>:
  match value:
    case Number{+decimal}:
      number.read(U32.read(decimal), decimal)
    case _:
      Fail{"Expected number in upstream data"}

def items(-A: Data, value: Value<A>) -> Result<&2, &2, String, Value<A>>:
  match value:
    case Array{items}:
      Done{items}
    case _:
      Fail{"Expected array in upstream data"}

def fields(-A: Data, value: Value<A>) -> Result<&2, &2, String, Value<A>>:
  match value:
    case Object{fields}:
      Done{fields}
    case _:
      Fail{"Expected object in upstream data"}

# Transform objects after their children. The callback never needs recursion.
def fold(~A: Data, ~object: Value<A> -> Result<&2, &2, String, Value<A>>, value: Value<Unit>) ->
  Result<&2, &2, String, Value<A>>:
  match value:
    case Null{}:
      Done{Null{}}
    case Boolean{value}:
      Done{Boolean{value}}
    case Number{value}:
      Done{Number{value}}
    case Text{value}:
      Done{Text{value}}
    case End{}:
      Done{End{}}
    case Decoded{_}:
      Fail{"Unexpected decoded host value"}
    case Array{items}:
      do Result<&2, &2, String, Value<A>>:
        items : Value<A> <- fold(~A, ~object, items)
        return Array{items}
    case Object{fields}:
      do Result<&2, &2, String, Value<A>>:
        fields : Value<A> <- fold(~A, ~object, fields)
        object(Object{fields})
    case Item{head, tail}:
      head tail = fold(~A, ~object, head) fold(~A, ~object, tail)
      do Result<&2, &2, String, Value<A>>:
        head : Value<A> <- head
        tail : Value<A> <- tail
        return Item{head, tail}
    case Field{name, head, tail}:
      head tail = fold(~A, ~object, head) fold(~A, ~object, tail)
      do Result<&2, &2, String, Value<A>>:
        head : Value<A> <- head
        tail : Value<A> <- tail
        return Field{name, head, tail}

def map(~A: Data, ~B: Data, ~read: Value<A> -> Result<&2, &2, String, B>, values: Value<A>) ->
  Result<&2, &2, String, List<&2, B>>:
  match values:
    case End{}:
      Done{Nil{}}
    case Item{head, tail}:
      do Result<&2, &2, String, List<&2, B>>:
        head : B <- read(head)
        tail : List<&2, B> <- map(~A, ~B, ~read, tail)
        return head <> tail
    case _:
      Fail{"Malformed upstream array"}

def array(~A: Data, ~B: Data, ~read: Value<A> -> Result<&2, &2, String, B>, value: Value<A>) ->
  Result<&2, &2, String, List<&2, B>>:
  do Result<&2, &2, String, List<&2, B>>:
    items : Value<A> <- items(A, value)
    map(~A, ~B, ~read, items)

def optional(-A: Data, -B: Data, read: Value<A> -> Result<&2, &2, String, B>, value: Value<A>) ->
  Result<&2, &2, String, Maybe<&2, B>>:
  match value:
    case Null{}:
      Done{None{}}
    case value:
      do Result<&2, &2, String, Maybe<&2, B>>:
        value : B <- read(value)
        return Some{value}
