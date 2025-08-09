# ZLisp

Embeddable Lisp for Zig.

## Data Types
### Ints
`int`s are `i32` variables.
```clojure
(def x 5) ;; define x to the current scope as 5
```

### Floats
`float`s are `f32` variables.
```clojure
(def x 5.0)
```

### Strings
Wrapper around `[]const u8`.
```clojure
(def x "hello, world")
```

### Symbols
A `[]const u8` that does not start with `"` and has no spaces.
```clojure
x ;; our x variable. On the repl, this will print it.
valid-symbol ;; as with any lisp, some special chars are allowed.
def ;; def is just a symbol.
```

### Keywords
A `[]const u8` that starts with `:`.
```clojure
:my-symbol ;; a symbol evaluates to itself.
```

### Nil
The `null` type.
```clojure
nil
```

### Functions
You can define functions with the `defun` symbol.
```clojure
(defun my-func [arg1 arg2]
    "doc string"
    (  ) ;; body
)
```
The first argument is a symbol, which is the function name, followed by a list/vector with the arguments names.
An optional docstring can be passed as the third argument. The final argument is the function body.

You define anonymous functions with the `fn` symbol. It takes a list/vector of symbols as parameters and a body
which is evaluated when called.
```clojure
(fn (a b) (+ a b)) ;; a function that sums a and b.
((fn (a b) (+ a b)) 1 2) ;; call the function with 1 and 2 as parameters.
```

You can define functions to the current environment with:
```clojure
(def my-func (fn* [a b] (+ a b)))
```

We also have closures
```clojure
(defun add-a [a]
    (fn [b] (+ a b))
```

Behind the scenes, all functions have the following signature:
```zig
fn (args: []LispType) LispError!LispType
```

### Lists
Lists are array lists which contains any number of ZLisp's variables. If the first element of the list
is a function, then it applies it with the other list elements as arguments. Any symbols will be evaluated
and added to the list.
```clojure
(1 2 3) ;; a list.
(1 "a" 5.0 nil) ;; lists can contain values of different types.
((1 2) "hello") ;; this includes other lists.
((fn (a b) (+ a b)) 1 2) ;; this will call the function with 1 and 2 as `a` and `b` respectively.
(a b c) ;; this will get the values of `a`, `b` and `c` and add it to the list. If `a` is function, it will be called with `b` and `c` as arguments.
(nth (1 2 3) 0) ;; 1
(nth (1 2 3) 2) ;; 3
(nth (1 2 3) 3) ;; nil
(head ()) ;; nil
(head (1 2 3)) ;; 1
(tail (1 2 3)) ;; (2 3)
(tail (1)) ;; ()
```

### Vectors
Vectors are also array lists. Any operations done on vectors can be done on lists. Vectors do not
evaluate functions inside it, however.
```clojure
[1 2 3] ;; a vector.
[1 "a" 5.0 nil] ;; vectors can contain values of different types.
[(fn (a b) (+ a b)] 1 2) ;; the function will not be applied, it is just an element of the vector.
((fn [a b] (+ a b)) 1 2) ;; will can use vectors as the function parameter list (you can not use it a body, though)
(nth [1 2 3] 0) ;; 1
(nth [1 2 3] 2) ;; 3
(nth [1 2 3] 3) ;; nil
(head []) ;; nil
(head [1 2 3]) ;; 1
(tail [1 2 3]) ;; [2 3]
(tail [1]) ;; []
```

### Dictionaries
Dictionaries can have `int`s, `boolean`s, `string`s and `keywords`s as keys. Anything can be used as the key value.
```clojure
(def my-dict {:a 1 :b 2 :c (1 2 3)}) ;; create a dict
(get my-dict :a) ;; return the value of :a, which is 1
(get my-dict :d) ;; :d is not a key, so `get` returns nil
(assoc my-dict :d "hello" :e 0.5) ;; returns a NEW hash map with the keys :d and :e, with values "hello" and 0.5
(dissoc my-dict :a :c) ;; returns a new dictionary without the keys :a and :c from `my-dict`
(contains? my-dict :a) ;; true
(contains? my-dict :d) ;; false
(keys my-dict) ;; returns a list containing the keys from my-dict
(values my-dict) ;; returns a list of the values from my-dict
```

### Booleans
Wrapper around `bool`.
```clojure
true
false
```
All values besides `false` and `nil` are considered as truthy values.

### Atoms
A mutable variable that holds a reference to another `lisp` value.
```clojure
(atom 5) ;; creates an atom which holds 5 as a value
(def a (atom "hello")) ;; binds the (atom "hello") to a
(deref a) ;; "hello"
(reset! a 5) ;; a now holds the value 5. Returns 5
(defun minus (a b c)
    (- a b c))
;; calls `minus` with the current value of `a` as the first argument and 3 and 4 as the second and third arguments.
;; the value returned by the function will be saved on the atom `a` and returns.
(swap! a minus 3 4)
```
