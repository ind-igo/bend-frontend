import ./core.bend as Core
import ./frontend.bend as Frontend
import ./decode.bend as Decode
import ./wire.bend as Wire

law bare_idempotent:
  for +term: Core.Term
  {Core.bare(Core.bare(term)) == Core.bare(term) : Core.Term}

law missing_laws_rejected:
  for program: Core.Program
  for closed: Bool
  for holes: U32
  for open: U32
  {Frontend.accept(program, True{}, closed, holes, open)
    == Fail{"PROOF.bend must import the adjacent LAWS.bend"} : Result<&2, &2, String, Core.Program>}

law complete_accepted:
  for +program: Core.Program
  {Frontend.accept(program, False{}, True{}, 0, 0) == Done{program} : Result<&2, &2, String, Core.Program>}

# Substitutions use Base.Either's actual constructors at the public boundary.
law substitution_term:
  for +term: Core.Term
  for nodes: Nat
  {Decode.substitution(Wire.Decoded{Decode.Term{term, nodes}}) == Done{Inl{term}}
    : Result<&2, &2, String, Either<&2, &2, Core.Term, Core.Pattern>>}

law substitution_pattern:
  for +pattern: Core.Pattern
  {Decode.substitution(Wire.Decoded{Decode.Pattern{pattern}}) == Done{Inr{pattern}}
    : Result<&2, &2, String, Either<&2, &2, Core.Term, Core.Pattern>>}

law metadata_overflow_rejected:
  {Wire.number(Unit, Wire.Number{"4294967296"}) == Fail{"Core metadata exceeds U32 range"}
    : Result<&2, &2, String, U32>}
