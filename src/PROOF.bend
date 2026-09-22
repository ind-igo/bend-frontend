import ./LAWS.bend as Laws
import ./core.bend as Core

def Laws.bare_idempotent(term):
  match term:
    case Core.TAnn{value, typ}:
      Laws.bare_idempotent(value)
    case Core.TVar{name, level, memo}:
      match memo:
        case Some{value}:
          Laws.bare_idempotent(value)
        case None{}:
          {==}
    case Core.TRef{_, _}:
      {==}
    case Core.TSub{_, _, _}:
      {==}
    case Core.TLet{_, _}:
      {==}
    case Core.TTyp{_}:
      {==}
    case Core.TQnt{}:
      {==}
    case Core.TQua{_}:
      {==}
    case Core.TMin{_, _}:
      {==}
    case Core.TAll{_, _, _, _, _}:
      {==}
    case Core.TLam{_, _, _, _}:
      {==}
    case Core.TApp{_, _}:
      {==}
    case Core.TADT{_, _, _}:
      {==}
    case Core.TCtr{_, _}:
      {==}
    case Core.TLit{_}:
      {==}
    case Core.TMat{_, _, _}:
      {==}
    case Core.TEfq{}:
      {==}
    case Core.TEql{_, _, _}:
      {==}
    case Core.TRfl{}:
      {==}
    case Core.TRwt{_, _, _}:
      {==}
    case Core.THol{_}:
      {==}

def Laws.missing_laws_rejected(program, closed, holes, open):
  {==}

def Laws.complete_accepted(program):
  {==}

def Laws.substitution_term(term, nodes):
  {==}

def Laws.substitution_pattern(pattern):
  {==}

def Laws.metadata_overflow_rejected():
  {==}
