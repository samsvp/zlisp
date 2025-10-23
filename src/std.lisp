(defmacro defn
  (fn
    "Defines a new function with the given name.
     Examples:
       (defn square [x] (* x x))
       (let [closure-arg 2] (defn add-2 [closure-arg] [a] (+ closure-arg a)))
       (let [five 5] (defn mult-5 \"docstring\" [five] [x] (* x five)))"
    [&args]
    (let [fn-name (first args)
          body (rest args)]
      ('def fn-name (cons 'fn body)))))

(defn inc
  "Returns x + 1"
  [x]
  (+ x 1))

(defn dec
  "Returns x - 1"
  [x]
  (- x 1))

(defn enumerate
  "Returns a tuple containing the index and value of each item in the collection.
   Examples:
   (= (enumerate [5 9 10]) [(0 5) (1 9) (2 10)])"
  [col]
  (let [counter (atom -1)]
    (map
      (fn [counter] [v]
        (let [i (swap! counter inc)]
          (i v)))
      col)))

(defn infix [infixed]
  ((nth infixed 1) (nth infixed 0) (nth infixed 2)))

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

(defn range
    "Creates a list from `from` to `to`, inclusive.
     Examples
        (= (range 0 10) (0 1 2 3 4 5 6 7 8 9 10))
        (= (range 25 20) (25 24 23 22 21 20))"
    [from to]
    (if (= from to)
      (to)
      (cons from (range
                    (if (< from to) (inc from) (dec from))
                    to))))

(defmacro while
  (fn
    [condition ast]
    ('if condition
      ('do ast ('while condition ast)))))

(defn zip
  "Returns a list of lists, where the i-th list contains the
   i-th element from each of the argument lists and vectors."
  [&col]
  (let [counter (atom -1)
        fst (first col)]
    (map
      (fn [counter col] [_]
        (let [i (swap! counter inc)]
          (map (fn [i] [lst] (nth lst i)) col)))
      fst)))

(defn reverse
  "Returns the given list/vector in reverse order."
  [lst]
  (let [counter (atom (count lst))]
    (map
      (fn [counter lst] [_]
        (let [i (swap! counter dec)]
          (nth lst i)))
      lst)))

(defn all
  "Returns true if all elements of the collection satisfies the given condition."
  [condition col]
  (if ( ->> col count (= 0) )
    true
    (if (condition (first col))
      (all condition (rest col))
      false)))

(defn any
  "Returns true if any element of the collection satisfies the given condition."
  [condition col]
  (if ( ->> col count (= 0) )
    false
    (if (condition (first col))
      true
      (all condition (rest col)))))

(defn sum
  "Sums all elements of the given list/vector."
  [col]
  (reduce + (first col) (rest col)))

(defn max
  "Returns the largest item of the given inputs."
  [&col]
  (reduce
    (fn [x y] (if (< x y) y x))
    (first col)
    (rest col)))

(defn min
  "Returns the smallest item of the given inputs."
  [&col]
  (reduce
    (fn [x y] (if (> x y) y x))
    (first col)
    (rest col)))

(defn slice
  "Returns a new list/vector with the elements from the original collection starting from
   'start' and ending at 'stop'. If 'stop' is negative, then its value will be (+ (count col) stop).
   Examples:
    (= (slice 1 1 (1 2 3 5 2 -1)) ())
    (= (slice 1 3 (1 2 3 5 2 -1)) (2 3))
    (= (slice 3 -1 (1 2 3 5 2 -1)) (5 2 -1))
    (= (slice 3 -2 [1 2 3 5 2 -1]) [5 2])"
  [start stop col]
  (let [counter (atom (- start 1))
        end (if (< stop 0)
              (->> col count (+ stop))
              (- stop 1))
        acc (if (list? col)
              (atom ())
              (atom []))]
    (do
      (while (< @counter end)
        (->> (swap! counter inc)
             (nth col)
             (conj! acc)))
      @acc)))

