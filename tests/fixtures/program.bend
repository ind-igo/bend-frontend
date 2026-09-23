import Base

type Tree is Data:
  Leaf{value: U32}
  Branch{left: Tree, right: Tree}

def sum(tree: Tree) -> U32:
  match tree:
    case Leaf{value}:
      value
    case Branch{left, right}:
      a b = sum(left) sum(right)
      (a + b : U32)

def adder(amount: U32) -> U32 -> U32:
  value => (value + amount : U32)

def twice(~f: U32 -> U32, value: U32) -> U32:
  f(f(value))

def identity(-A: Type, value: A) -> A:
  value

def square(+value: U32) -> U32:
  (value * value : U32)

def array_value() -> Array<U32> & U32:
  a = [0 : U32*8n]
  a[5] <- 42
  a[5]

def main() -> U32:
  tree = {Branch{Leaf{10}, Branch{Leaf{20}, Leaf{5}}} : Tree}
  add5 = adder(5)
  add5(twice(~(x => (x + 1 : U32)), sum(tree)))

#|42
