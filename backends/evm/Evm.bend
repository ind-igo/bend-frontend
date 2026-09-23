import Base

# The contract model. Words are Nat below the state's limit (2^256 on the EVM).
# Storage is an association list: the newest slot wins, missing slots are zero.
type Slot is Data:
  Slot{key: Nat, value: Nat}

type State is Data:
  State{storage: List<&2, Slot>, caller: Nat, limit: Nat}

# The limit is state, not a constant: a symbolic limit keeps proofs from
# expanding 2^256 as a unary Nat. Laws proved for every limit hold on the EVM.

# A revert discards every state change, so it carries no state.
type Outcome<-A: Data> is Data:
  Ok{value: A, state: State}
  Revert{}

def Contract(-A: Data) -> Type:
  State -> Outcome<A>

def Contract.pure(-A: Data, x: A) -> Contract(A):
  s => Ok{x, s}

def Contract.next(-A: Data, -B: Data, r: Outcome<A>, f: A -> Contract(B)) -> Outcome<B>:
  match r:
    case Ok{value, state}:
      f(value, state)
    case Revert{}:
      Revert{}

def Contract.bind(-A: Data, -B: Data, m: Contract(A), f: A -> Contract(B)) -> Contract(B):
  s => Contract.next(A, B, m(s), f)

def lookup(storage: List<&2, Slot>, +key: Nat) -> Nat:
  match storage:
    case Nil{}:
      0n
    case Slot{k, v} <> rest:
      Bool.pick(Nat, Nat.is_eq(k, key), v, lookup(rest, key))

def sload.go(+key: Nat, s: State) -> Outcome<Nat>:
  match s:
    case State{+storage, caller, limit}:
      Ok{lookup(storage, key), State{storage, caller, limit}}

def sload(key: Nat) -> Contract(Nat):
  s => sload.go(key, s)

def sstore.go(key: Nat, value: Nat, s: State) -> Outcome<Unit>:
  match s:
    case State{storage, caller, limit}:
      Ok{Unit{}, State{Slot{key, value} <> storage, caller, limit}}

def sstore(key: Nat, value: Nat) -> Contract(Unit):
  s => sstore.go(key, value, s)

def caller.go(s: State) -> Outcome<Nat>:
  match s:
    case State{storage, +caller, limit}:
      Ok{caller, State{storage, caller, limit}}

def caller() -> Contract(Nat):
  s => caller.go(s)

def require.go(ok: Bool, s: State) -> Outcome<Unit>:
  match ok:
    case True{}:
      Ok{Unit{}, s}
    case False{}:
      Revert{}

def require(ok: Bool) -> Contract(Unit):
  s => require.go(ok, s)

def add.go(+sum: Nat, fits: Bool, s: State) -> Outcome<Nat>:
  match fits:
    case True{}:
      Ok{sum, s}
    case False{}:
      Revert{}

def add.sum(+sum: Nat, s: State) -> Outcome<Nat>:
  match s:
    case State{storage, caller, +limit}:
      add.go(sum, Nat.is_lt(sum, limit), State{storage, caller, limit})

# Checked addition: reverts on overflow, like Solidity 0.8.
def add(a: Nat, b: Nat) -> Contract(Nat):
  s => add.sum(Nat.add(a, b), s)
