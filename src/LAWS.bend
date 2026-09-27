import ./core.bend as Core
import ./decode.bend as Decode
import ./wire.bend as Wire

law bare_idempotent:
  for +term: Core.Term
  {Core.bare(Core.bare(term)) == Core.bare(term) : Core.Term}

law missing_laws_rejected:
  for program: Core.Program
  for holes: U32
  {Decode.accept(program, True{}, holes)
    == Fail{"PROOF.bend must import the adjacent LAWS.bend"} : Result<&2, &2, String, Core.Program>}

law complete_accepted:
  for +program: Core.Program
  {Decode.accept(program, False{}, 0) == Done{program} : Result<&2, &2, String, Core.Program>}

law metadata_overflow_rejected:
  {Wire.number(Unit, Wire.Number{"4294967296"}) == Fail{"Core metadata exceeds U32 range"}
    : Result<&2, &2, String, U32>}
