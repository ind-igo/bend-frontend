import Base
import ../Evm.bend as Evm

def owner() -> Nat:
  7n

def get() -> Evm.Contract(Nat):
  Evm.sload(0n)

def increment() -> Evm.Contract(Unit):
  do Evm.Contract<Unit>:
    n : Nat <- Evm.sload(0n)
    m : Nat <- Evm.add(n, 1n)
    Evm.sstore(0n, m)

def set(value: Nat) -> Evm.Contract(Unit):
  do Evm.Contract<Unit>:
    who : Nat <- Evm.caller()
    Evm.require(Nat.is_eq(who, owner()))
    Evm.sstore(0n, value)
