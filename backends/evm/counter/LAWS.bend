import Base
import ../Evm.bend as Evm
import ./program.bend as Counter

# The owner stores any value; the storage and word limit stay symbolic.
law set_by_owner:
  for storage: List<&2, Evm.Slot>
  for limit: Nat
  for +value: Nat
  {Counter.set(value, Evm.State{storage, Counter.owner(), limit})
    == Evm.Ok{Unit{}, Evm.State{Evm.Slot{0n, value} <> storage, Counter.owner(), limit}} : Evm.Outcome<Unit>}

law set_by_other:
  for storage: List<&2, Evm.Slot>
  for limit: Nat
  for value: Nat
  {Counter.set(value, Evm.State{storage, 8n, limit}) == Evm.Revert{} : Evm.Outcome<Unit>}

law get_after_set:
  for storage: List<&2, Evm.Slot>
  for limit: Nat
  for +value: Nat
  {Counter.get(Evm.State{Evm.Slot{0n, value} <> storage, 7n, limit})
    == Evm.Ok{value, Evm.State{Evm.Slot{0n, value} <> storage, 7n, limit}} : Evm.Outcome<Nat>}
