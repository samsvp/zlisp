## Builtin Functions

- **`eval`** `[expr]`: Evaluates `expr`.
    ```clojure
    (eval '(+ 1 2)) ; => 3
    (eval '(* 2 4)) ; => 8
    ```

- **`try`** `[form (catch symbol handler)]`: Evaluates `form`. If it throws an error, binds the error message to `symbol` and evaluates `handler` in that context. Returns the result of `form` if no error occurs.
    ```clojure
    (try (/ 1 0) (catch err (str "Error: " err))) ; => "Error: division by zero"
    (try (+ 1 2) (catch err (str "Error")))       ; => 3
    ```

- **`throw`** `[msg]`: Throws a runtime error with the given string message. Immediately terminates evaluation.
    ```clojure
    (throw "Something went wrong") ; Throws: "Something went wrong"
    ```

- **`quote`** `[form]`: Returns `form` unevaluated. Prevents evaluation of its argument.
    ```clojure
    (quote (+ 1 2)) ; => (+ 1 2)
    '(+ 1 2) ; => (+ 1 2)
    (quote x)       ; => x
    ```

- **`quasiquote`** `[form]`: Enables selective evaluation within a quoted structure. Use `unquote` (`~`) to escape and evaluate, and `splice-unquote` (`~@`) to splice a sequence into the list/vector.
    ```clojure
    (quasiquote (1 2 ~(+ 1 2) 4))     ; => (1 2 3 4)
    `(1 2 ~(+ 1 2) 4)     ; => (1 2 3 4)
    (quasiquote (1 2 ~@(list 3 4) 5)) ; => (1 2 3 4 5)
    ```

- **`def`** `[symbol value]`: Binds `symbol` globally to the evaluated `value`. Returns `value`.
    ```clojure
    (def x 42)   ; => 42
    x            ; => 42
    (def y (+ 1 2)) ; => 3
    ```

- **`defmacro`** `[name macro-body]`: Defines a macro named `name` whose body is a function that transforms unevaluated arguments at compile-time. The resulting form replaces the macro call during evaluation.
    ```clojure
    (defmacro when [cond body]
      (list 'if cond (list 'do body)))
    (when (> x 0) (print "positive")) ; Expands to (if (> x 0) (do (print "positive")))
    ```

- **`if`** `[condition then [else]]`: Evaluates `condition`. If truthy (not `nil` or `false`), evaluates and returns `then`. Otherwise, evaluates and returns `else` if provided; otherwise returns `nil`.
    ```clojure
    (if (> 5 3) "yes" "no") ; => "yes"
    (if nil "a" "b")        ; => "b"
    (if true "yes")         ; => "yes"
    ```

- **`let`** `[binding-vector body]`: Creates a new lexical scope. Binds symbols in `binding-vector` (a vector of alternating key-value pairs) to their evaluated values, then evaluates `body` in that scope.
    ```clojure
    (let [x 1 y 2] (+ x y)) ; => 3
    (let [a 10 b (+ a 5)] (* a b)) ; => 150
    ```

- **`fn`** `[params body]` / `[docstring params body]` / `[closures params body]`: Creates an anonymous function. Parameters are given as a vector. Optionally accepts a docstring or closure bindings (symbols captured from the defining environment).
    ```clojure
    (fn [x y] (+ x y))              ; => #function
    (fn "adds two numbers" [x y] (+ x y))
    (fn [x] [x] (+ x 1))            ; Captures the vector [x] as a closure
    ```

- **`do`** `[form1 form2 ... formN]`: Evaluates each form sequentially and returns the result of the last one. Used for sequencing side effects.
    ```clojure
    (do (print "hello") (print "world") 42) ; Prints both strings, returns 42
    (do (def x 1) (def y 2) (+ x y))        ; => 3
    ```

- **`not`** `[x]`: Returns `true` if `x` is `nil` or `false`; otherwise returns `false`.
    ```clojure
    (not nil)       ; => true
    (not false)     ; => true
    (not 0)         ; => false
    (not true)      ; => false
    ```

- **`true?`** `[x]`: Returns `x` if it is `true`; otherwise returns `false`.
    ```clojure
    (true? true)    ; => true
    (true? false)   ; => false
    (true? 1)       ; => false
    (true? nil)     ; => false
    ```

- **`false?`** `[x]`: Returns `true` if `x` is `false`; otherwise returns `false`.
    ```clojure
    (false? false)  ; => true
    (false? true)   ; => false
    (false? nil)    ; => false
    (false? 0)      ; => false
    ```

- **`=`** `[x y & more]`: Returns `true` if all arguments are equal (using `.eql()`); `false` otherwise.
    ```clojure
    (= 1 1)         ; => true
    (= 1 2)         ; => false
    (= "a" "a")     ; => true
    (= 1 1 1)       ; => true
    (= 1 1 2)       ; => false
    ```

- **`!=`** `[x y & more]`: Returns `true` if any two arguments are not equal; `false` if all are equal.
    ```clojure
    (!= 1 2)        ; => true
    (!= 1 1)        ; => false
    (!= 1 1 2)      ; => true
    ```

- **`<`** `[x y & more]`: Returns `true` if each number is strictly less than the next.
    ```clojure
    (< 1 2 3)       ; => true
    (< 3 2)         ; => false
    (< 1.5 2.0)     ; => true
    ```

- **`<=`** `[x y & more]`: Returns `true` if each number is less than or equal to the next.
    ```clojure
    (<= 1 1 2)      ; => true
    (<= 2 1)        ; => false
    (<= 1.0 1.0)    ; => true
    ```

- **`>`** `[x y & more]`: Returns `true` if each number is strictly greater than the next.
    ```clojure
    (> 3 2 1)       ; => true
    (> 1 2)         ; => false
    (> 2.5 2.0)     ; => true
    ```

- **`>=`** `[x y & more]`: Returns `true` if each number is greater than or equal to the next.
    ```clojure
    (>= 3 3 2)      ; => true
    (>= 1 2)        ; => false
    (>= 2.0 2.0)    ; => true
    ```

- **`+`** `[x y & more]`: Adds numbers, strings, lists, or vectors. Type is determined by the first argument.
    ```clojure
    (+ 1 2 3)       ; => 6
    (+ 1.5 2.5)     ; => 4.0
    (+ "hello" " " "world") ; => "hello world"
    (+ [1 2] [3 4]) ; => [1 2 3 4]
    ```

- **`-`** `[x y & more]`: Subtracts subsequent arguments from the first. If only one argument, negates it.
    ```clojure
    (- 10 3 2)      ; => 5
    (- 5)           ; => -5
    (- 3.0 1.0)     ; => 2.0
    ```

- **`*`** `[x y & more]`: Multiplies numbers.
    ```clojure
    (* 2 3 4)       ; => 24
    (* 1.5 2)       ; => 3.0
    ```

- **`/`** `[x y & more]`: Divides the first argument by each subsequent argument. Throws division-by-zero error if divisor is zero.
    ```clojure
    (/ 10 2)        ; => 5
    (/ 7 2)         ; => 3 (integer floor division)
    (/ 7.0 2.0)     ; => 3.5
    ```

- **`%`** `[dividend divisor]`: Returns the remainder of dividing `dividend` by `divisor`. Throws division-by-zero error if divisor is zero.
    ```clojure
    (%) 10 3)       ; => 1
    (% 7.5 2.0)     ; => 1.5
    ```

- **`map`** `[f coll]`: Applies function `f` to each element of collection (`list` or `vector`) and returns a new collection of results.
    ```clojure
    (map inc [1 2 3])     ; => [2 3 4]
    (map str '("a" "b"))  ; => ("a" "b")
    ```

- **`filter`** `[pred coll]`: Returns a new collection containing only elements for which `pred` returns truthy.
    ```clojure
    (filter even? [1 2 3 4]) ; => [2 4]
    (filter pos? [-1 0 1])   ; => [1]
    ```

- **`reduce`** `[f init coll]`: Applies binary function `f` cumulatively to elements of `coll`, starting with `init`.
    ```clojure
    (reduce + 0 [1 2 3])     ; => 6
    (reduce * 1 [1 2 3 4])   ; => 24
    (reduce conj [] '(1 2))  ; => [1 2]
    ```

- **`apply`** `[f args... last-coll]`: Calls function `f` with all arguments flattened: `(apply f a b [c d])` → `(f a b c d)`.
    ```clojure
    (apply + 1 2 [3 4])      ; => 10
    (apply list 1 2 '(3 4))  ; => (1 2 3 4)
    ```

- **`dict`** `[k v k v ...]`: Creates a dictionary from alternating key-value pairs.
    ```clojure
    (dict :a 1 :b 2)         ; => { :a 1, :b 2 }
    (dict "x" 10 "y" 20)     ; => { "x" 10, "y" 20 }
    ```

- **`assoc`** `[dict k v k v ...]`: Returns a new dict with additional or updated key-value pairs.
    ```clojure
    (assoc {:a 1} :b 2)      ; => { :a 1, :b 2 }
    (assoc {:a 1} :a 99)     ; => { :a 99 }
    ```

- **`dissoc`** `[dict k & more]`: Returns a new dict without the specified keys.
    ```clojure
    (dissoc {:a 1 :b 2} :a)  ; => { :b 2 }
    (dissoc {:a 1 :b 2} :a :b) ; => {}
    ```

- **`get`** `[dict key]`: Returns the value associated with `key`, or `nil` if not found.
    ```clojure
    (get {:a 1} :a)          ; => 1
    (get {:a 1} :b)          ; => nil
    ```

- **`contains?`** `[dict key]`: Returns `true` if `key` exists in `dict`; `false` otherwise.
    ```clojure
    (contains? {:a 1} :a)    ; => true
    (contains? {:a 1} :b)    ; => false
    ```

- **`keys`** `[dict]`: Returns a list of all keys in the dictionary.
    ```clojure
    (keys {:a 1 :b 2})       ; => (:a :b)
    ```

- **`values`** `[dict]`: Returns a list of all values in the dictionary.
    ```clojure
    (values {:a 1 :b 2})     ; => (1 2)
    ```

- **`list`** `[x y & more]`: Returns a new list containing the evaluated arguments.
    ```clojure
    (list 1 (+ 2 3) "a")     ; => (1 5 "a")
    ```

- **`vector`** `[x y & more]`: Returns a new vector containing the evaluated arguments.
    ```clojure
    (vector 1 2 3)           ; => [1 2 3]
    ```

- **`vec`** `[coll]`: Converts a list or vector into a vector.
    ```clojure
    (vec '(1 2 3))           ; => [1 2 3]
    (vec [1 2 3])            ; => [1 2 3]
    ```

- **`nth`** `[coll n]`: Returns the element at index `n` (0-based). Throws error if out of bounds.
    ```clojure
    (nth [1 2 3] 1)          ; => 2
    (nth "hello" 0)          ; => "h"
    ```

- **`first`** / **`head`** `[coll]`: Returns the first element of a list, vector, or string.
    ```clojure
    (first [1 2 3])          ; => 1
    (head "abc")             ; => "a"
    ```

- **`rest`** / **`tail`** `[coll]`: Returns a new collection with all but the first element.
    ```clojure
    (rest [1 2 3])           ; => [2 3]
    (tail "hello")           ; => "ello"
    ```

- **`list?`** `[x]`: Returns `true` if `x` is a list; `false` otherwise.
    ```clojure
    (list? '(1 2))           ; => true
    (list? [1 2])            ; => false
    ```

- **`vector?`** `[x]`: Returns `true` if `x` is a vector; `false` otherwise.
    ```clojure
    (vector? [1 2])          ; => true
    (vector? '(1 2))         ; => false
    ```

- **`sequential?`** `[x]`: Returns `true` if `x` is a list or vector; `false` otherwise.
    ```clojure
    (sequential? '(1 2))     ; => true
    (sequential? [1 2])      ; => true
    (sequential? {:a 1})     ; => false
    ```

- **`dict?`** `[x]`: Returns `true` if `x` is a dictionary; `false` otherwise.
    ```clojure
    (dict? {:a 1})           ; => true
    (dict? [1 2])            ; => false
    ```

- **`empty?`** `[coll]`: Returns `true` if `coll` is empty (list, vector, or dict); `false` otherwise.
    ```clojure
    (empty? '())             ; => true
    (empty? [1])             ; => false
    (empty? {})              ; => true
    ```

- **`count`** `[coll]`: Returns the number of elements in a list, vector, or dict.
    ```clojure
    (count [1 2 3])          ; => 3
    (count {:a 1 :b 2})      ; => 2
    (count "")               ; => 0
    ```

- **`cons`** `[x coll]`: Prepends `x` to a list or vector, returning a new collection of the same type.
    ```clojure
    (cons 0 [1 2])           ; => [0 1 2]
    (cons 0 '(1 2))          ; => (0 1 2)
    ```

- **`conj`** `[coll x]`: Appends `x` to a list or vector, returning a new collection of the same type.
    ```clojure
    (conj [1 2] 3)           ; => [1 2 3]
    (conj '(1 2) 3)          ; => (3 1 2) ; Note: cons-style prepend for lists
    ```

- **`conj!`** `[atom-coll x]`: Mutates an atom holding a list or vector by appending `x` to it.
    ```clojure
    (def a (atom [1 2]))
    (conj! a 3)
    @a                        ; => [1 2 3]
    ```

- **`concat`** `[coll1 coll2 & more]`: Concatenates multiple lists or vectors into one.
    ```clojure
    (concat [1 2] '(3 4))    ; => [1 2 3 4]
    (concat '() [1] '(2))    ; => [1 2]
    ```

- **`atom`** `[x]`: Creates an atom holding the value `x`.
    ```clojure
    (atom 42)                ; => #atom[42]
    (atom [1 2 3])           ; => #atom[[1 2 3]]
    ```

- **`atom?`** `[x]`: Returns `true` if `x` is an atom; `false` otherwise.
    ```clojure
    (atom? (atom 1))         ; => true
    (atom? 1)                ; => false
    ```

- **`deref`** `[atom]`: Returns the current value held by the atom.
    ```clojure
    (deref (atom 42))        ; => 42
    @(atom 42)        ; => 42
    ```

- **`reset!`** `[atom new-val]`: Replaces the value of the atom with `new-val`.
    ```clojure
    (def a (atom 1))
    (reset! a 99)
    @a                        ; => 99
    ```

- **`swap!`** `[atom f & args]`: Atomically replaces the atom’s value with `(apply f (current-value) args...)`.
    ```clojure
    (def a (atom 0))
    (swap! a + 10)           ; => 10
    (swap! a * 2)            ; => 20
    ```

- **`symbol`** `[str]`: Creates a symbol from a string.
    ```clojure
    (symbol "x")             ; => x
    (symbol "my-var")        ; => my-var
    ```

- **`keyword`** `[str-or-keyword]`: Creates a keyword from a string, or returns the keyword unchanged.
    ```clojure
    (keyword "a")            ; => :a
    (keyword :b)             ; => :b
    ```

- **`nil?`** `[x]`: Returns `true` if `x` is `nil`; `false` otherwise.
    ```clojure
    (nil? nil)               ; => true
    (nil? 0)                 ; => false
    ```

- **`bool?`** `[x]`: Returns `true` if `x` is a boolean; `false` otherwise.
    ```clojure
    (bool? true)             ; => true
    (bool? 1)                ; => false
    ```

- **`symbol?`** `[x]`: Returns `true` if `x` is a symbol; `false` otherwise.
    ```clojure
    (symbol? x)              ; => true
    (symbol? "x")            ; => false
    ```

- **`keyword?`** `[x]`: Returns `true` if `x` is a keyword; `false` otherwise.
    ```clojure
    (keyword? :a)            ; => true
    (keyword? "a")           ; => false
    ```

- **`int?`** `[x]`: Returns `true` if `x` is an integer; `false` otherwise.
    ```clojure
    (int? 42)                ; => true
    (int? 42.0)              ; => false
    ```

- **`float?`** `[x]`: Returns `true` if `x` is a float; `false` otherwise.
    ```clojure
    (float? 3.14)            ; => true
    (float? 3)               ; => false
    ```

- **`str`** `[x y & more]`: Converts all arguments to strings and concatenates them.
    ```clojure
    (str "a" 1 true)         ; => "a1true"
    (str 100 " items")       ; => "100 items"
    ```

- **`read-str`** `[s]`: Parses a string as Lisp syntax and returns the resulting value.
    ```clojure
    (read-str "(+ 1 2)")     ; => (+ 1 2)
    (read-str "[:a :b]")     ; => [:a :b]
    ```

- **`slurp`** `[path]`: Reads entire contents of file at `path` as a string.
    ```clojure
    (slurp "data.txt")       ; => "file content..."
    ```

- **`help`** `[fn]`: Returns the docstring of a function, or `#builtint` for built-ins.
    ```clojure
    (help map)               ; => "Applies 'f' to each element..."
    (help +)                 ; => "#builtint"
    ```

- **`load-file`** `[path]`: Reads and evaluates the entire content of a file as Lisp code.
    ```clojure
    (load-file "script.clj") ; => result of evaluating script
    ```

- **`arrow-first`** `[val f1 f2 ...]`: Threads `val` as the *last* argument through each function.
    ```clojure
    (arrow-first 5 inc dec)  ; => (dec (inc 5)) => 5
    (arrow-first 1 list inc) ; => (list 1 inc) => (1 #function)
    ```

- **`arrow-last`** `[val f1 f2 ...]`: Threads `val` as the *first* argument through each function.
    ```clojure
    (arrow-last 5 inc dec)   ; => (dec (inc 5)) => 5
    (arrow-last 1 + 2)       ; => (+ 1 2) => 3
    ```

- **`inc`** `[x]`: Returns `x + 1`. Works on integers and floats.
    ```clojure
    (inc 5)     ; => 6
    (inc -1)    ; => 0
    (inc 3.14)  ; => 4.14
    ```

- **`dec`** `[x]`: Returns `x - 1`. Works on integers and floats.
    ```clojure
    (dec 5)     ; => 4
    (dec 0)     ; => -1
    (dec 3.14)  ; => 2.14
    ```

- **`enumerate`** `[collection]`: Returns a list of tuples `(index value)` for each item in the collection.
    ```clojure
    (= (enumerate [5 9 10]) [(0 5) (1 9) (2 10)])
    (= (enumerate '(:a :b)) ((0 :a) (1 :b)))
    ```

- **`infix`** `[lst]`: Converts an infix expression `(value1 operand value2)` into prefix form `(operand value1 value2)`.
    ```clojure
    (= (infix (1 + 2)) (+ 1 2))
    (= (infix (10 * 3)) (* 10 3))
    (= (infix (a > b)) (> a b))
    ```

- **`cond`** `[&xs]`: Takes pairs of conditions and values. Returns the value associated with the first truthy condition. Returns `nil` if no condition is true.
    ```clojure
    (= (cond false 8 true 7) 7)
    (= (cond false 8 false 7) nil)
    (def x 5)
    (= (cond (> x 10) "big" (< x 0) "neg" :else "mid") "mid")
    ```

- **`while`** `[condition-ast] [body-ast]`: Evaluates the `body-ast` repeatedly while the `condition-ast` evaluates to a truthy value. Returns the result of the last evaluation of `body-ast`, or `nil` if never executed.
    ```clojure
    (def x (atom 10))
    (while (> @x 0) (swap! x dec))
    ```

- **`zip`** `[&collections]`: Returns a list of lists, where the i-th inner list contains the i-th element from each of the provided collections. Stops at the shortest collection.
    ```clojure
    (= (zip (1 2 3) (4 5 6)) ((1 4) (2 5) (3 6)))
    (= (zip [:a :b] [1 2 3]) ((:a 1) (:b 2)))
    ```

- **`reverse`** `[lst]`: Returns a new list or vector containing the elements of the input in reverse order.
    ```clojure
    (= (reverse (1 2 3)) (3 2 1))
    (= (reverse [1 2 3]) [3 2 1])
    (= (reverse "hello") "olleh")
    ```

- **`all`** `[predicate-fn collection]`: Returns `true` if `predicate-fn` returns truthy for every element in the collection. Returns `true` for empty collections.
    ```clojure
    (= (all pos? [1 2 3]) true)
    (= (all pos? [1 -2 3]) false)
    (= (all int? '(1 2 3)) true)
    (= (all even? '()) true)
    ```

- **`any`** `[predicate-fn collection]`: Returns `true` if `predicate-fn` returns truthy for any element in the collection. Returns `false` for empty collections.
    ```clojure
    (= (any neg? [1 2 -3]) true)
    (= (any neg? [1 2 3]) false)
    (= (any even? '()) false)
    ```

- **`sum`** `[col]`: Returns the sum of all numeric elements in the collection. Supports integers and floats.
    ```clojure
    (= (sum [1 2 3]) 6)
    (= (sum '(1.5 2.5)) 4.0)
    (= (sum []) 0)
    ```

- **`max`** `[&col]`: Returns the largest value among the given numbers. At least one argument required.
    ```clojure
    (= (max 1 2 3) 3)
    (= (max 1.5 2.5 0.5) 2.5)
    (= (max -1 -5 -2) -1)
    ```

- **`min`** `[&col]`: Returns the smallest value among the given numbers. At least one argument required.
    ```clojure
    (= (min 1 2 3) 1)
    (= (min 1.5 2.5 0.5) 0.5)
    (= (min -1 -5 -2) -5)
    ```

- **`slice`** `[start stop col]`: Returns a new list or vector containing elements from index `start` (inclusive) to `stop` (exclusive). If `stop` is negative, it’s interpreted as `(+ (count col) stop)`.
    ```clojure
    (= (slice 1 1 (1 2 3 5 2 -1)) ())
    (= (slice 1 3 (1 2 3 5 2 -1)) (2 3))
    (= (slice 3 -1 (1 2 3 5 2 -1)) (5 2 -1))
    (= (slice 3 -2 [1 2 3 5 2 -1]) [5 2])
    ```
