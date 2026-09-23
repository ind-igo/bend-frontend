import Base

def calculate(a: U32, b: U32, c: U32) -> U32:
  product = (a * b : U32)
  (product + c : U32)

# Independent RHS scopes reuse binder levels; each result must keep its value.
def scopes(+a: U32, +b: U32, +c: U32) -> U32:
  x y = U32.add((
    p = (a * b : U32)
    p
  ), c) U32.add((
    q = (b * c : U32)
    q
  ), a)
  (x * y : U32)
