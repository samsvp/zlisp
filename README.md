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
:my-symbol ;; a keyword evaluates to itself.
```

### Nil
The `null` type.
```clojure
nil
```

### Functions
You can define functions with the `defun` symbol.
```clojure
(defn my-func
    "doc string"
    [arg1 arg2]
    (  ) ;; body
)
```
The first argument is a symbol, which is the function name, followed by a vector with the arguments names.
If two vectors are passed, the first will be closure's capture group while the second will be the parameter list.
An optional docstring can be passed as the first argument after the function name. The final argument is the function body.

You define anonymous functions with the `fn` symbol. It takes a vector of symbols as parameters and a body
which is evaluated when called.
```clojure
(fn [a b] (+ a b)) ;; a function that sums a and b.
((fn [a b] (+ a b)) 1 2) ;; call the function with 1 and 2 as parameters.
```

You can define functions to the current environment with:
```clojure
(def my-func (fn* "docstring" [closure] [a b] (+ a b)))
```
or
```clojure
(defn my-func "docstring" [closure] [a b] (+ a b))
```
`defn` is just a macro that expands to `(def my-func (fn "docstring" [closure] [args] (body)))`

We also have closures
```clojure
(defn add-a [a]
    (fn [a] [b] (+ a b))
```
You need to specify which variables you are capturing in the closure. These will be copied to the function environment.

Behind the scenes, all functions have the following signature:
```zig
fn (args: []LispType) LispError!LispType
```
You can add custom zig functions by calling
```zig
fn myFn(args: []LispType) LispError!LispType {
    // code
}
try env.mapping.put(allocator, "fn-name", LispType.Function.createBuiltin(allocator, myFn));
```

You can also call `(help fn-name)` to get a function's `docstring`.

### Macros
Macros are created using the `defmacro` symbol
```clojure
(defmacro cond
  (fn [&xs]
    (if (> (count xs) 0)
      ('if (head xs)
        (if (> (count xs) 1)
          (nth xs 1)
          (throw "odd number of forms to cond"))
        (cons 'cond (tail (tail xs)))))))

(defmacro for
  (fn
    "Python like list comprehension.
     Examples
       (= (for x :in [1 2 3] (* 2 x)) [2 4 6])
       (defn square [x] (* x x))
       (= (for x :in (1 2 3) (square x)) (1 4 9))"
    [value in col ast]
    (if (= in :in)
      ('map ('fn [value] ast) col)
      (throw "'for' macro missing ':in' keyword"))))
```
these examples are the actual code from the standard library written in zlisp.

### Lists
Lists are array lists which contains any number of ZLisp's variables. If the first element of the list
is a function, then it applies it with the other list elements as arguments. Any symbols will be evaluated
and added to the list.
```clojure
(list 1 2 3) ;; a list.
(list 1 "a" 5.0 nil) ;; lists can contain values of different types.
(list (list 1 2) "hello") ;; this includes other lists.
((fn (a b) (+ a b)) 1 2) ;; this will call the function with 1 and 2 as `a` and `b` respectively.
(a b c) ;; If `a` is function, it will be called with `b` and `c` as arguments.
(nth (list 1 2 3) 0) ;; 1
(nth (list 1 2 3) 2) ;; 3
(nth (list 1 2 3) 3) ;; nil
(head (list)) ;; nil
(first (list)) ;; nil
(first (list 1 2 3)) ;; 1
(tail (list 1 2 3)) ;; (2 3)
(rest (list)) ;; nil
(rest (list 1)) ;; ()
```

### Vectors
Vectors are also array lists. Any operations done on vectors can be done on lists. Vectors do not
evaluate functions inside it, however.
```clojure
[1 2 3] ;; a vector.
[1 "a" 5.0 nil] ;; vectors can contain values of different types.
[(fn [a b] (+ a b)) 1 2] ;; the function will not be applied, it is just an element of the vector.
(nth [1 2 3] 0) ;; 1
(nth [1 2 3] 2) ;; 3
(nth [1 2 3] 3) ;; nil
(first []) ;; nil
(first [1 2 3]) ;; 1
(rest [1 2 3]) ;; [2 3]
(rest [1]) ;; []
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
(defun minus [a b c]
    (- a b c))
;; calls `minus` with the current value of `a` as the first argument and 3 and 4 as the second and third arguments.
;; the value returned by the function will be saved on the atom `a` and returns.
(swap! a minus 3 4)
```

## Zig interop
You can add custom zig functions by calling
```zig
fn myFn(args: []LispType) LispError!LispType {
    // code
}
try env.mapping.put(allocator, "fn-name", LispType.Function.createBuiltin(allocator, myFn));
```
You can also add `zig` structs to the `zlisp` language. All `structs` will be converted to `zlisp`
records. To add a custom zig struct, first define a struct with a `copy`function with the following signature
`pub fn clone(self: Self, allocator: std.mem.Allocator) Self`. `zlisp` has a sample `Enum` type witch is actually
a custom zig struct named `Enum`.
```zig
/// An example on how to use a record to hold user defined data types.
/// This is just a C like enum, with names and an int value.
pub const Enum = struct {
    options: [][]const u8,
    selected: usize,

    const Self = @This();

    pub fn init(options: [][]const u8, selected: usize) !Self {
        if (selected >= options.len) {
            return error.ValueOutOfRange;
        }

        return Self{
            .options = options,
            .selected = selected,
        };
    }

    /// Any value that can become a lisp type must implement a clone function.
    /// This will be called when setting the value to the global environment (i.e. when using the
    /// `def` function) or when returning the value from an expression.
    pub fn clone(self: Self, allocator: std.mem.Allocator) Self {
        var new_options = std.ArrayListUnmanaged([]const u8).initCapacity(allocator, self.options.len) catch outOfMemory();
        for (self.options) |opts| {
            const o = allocator.dupe(u8, opts) catch outOfMemory();
            new_options.appendAssumeCapacity(o);
        }

        return .{
            .options = new_options.items,
            .selected = self.selected,
        };
    }
};
```
This is the code to create a new `Enum` from `zlisp`
```zig
/// Create an enum. Takes a dict containing the struct field as keys with its respective
/// values. e.g. (enum-init { "selected" 1 "options" (:hello :world) }).
/// @argument selected: dict[string,lisp_type]
/// @return: the newly created enum.
pub fn enumInit(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments("enum-init", 1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    return LispType.Record.fromDict(Enum, allocator, args[0]) catch err_ctx.invalidCast("enum-init", "enum");
}
```
`LispType.Record.fromDict` can convert a `zlisp` dictionary to any zig struct, as long as all of the dict's keys are
strings. Here is how each `LispType` is converted into a zig type:
```
string -> []const u8;
keyword -> []const u8;
symbol -> []const u8;
int -> any integer type;
float -> any float type;
list -> []T;
array -> []T ;
dict -> StringHashMapUnmanaged(T);
bool -> bool;
```
`functions`, `records` and `nil` can not be converted using `LispType.Record.fromDict`. An `atom` is converted to its underlying value.
To cast a `record` to its underlying type `T`, call `var.as(T)`. It return a `*T` if successful or `null` if the conversion could
not be made. Look at the `enum` functions from `lisp_std.zig` (`enumInit`, `enumIndex`, `enumSelected`}) for more examples on
how records work.
